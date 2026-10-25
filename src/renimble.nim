import std/[os, parseopt, strutils, options, tables]
import renimble/[types, version, declarative_parser, rewriter, lockfile, config, registry, engine, pr, github_actions, atlas, dismissal, solver, compiler]

const RenimbleVersion = "0.1.1"

type
  CliMode = enum
    cmReport,  # Default local: inspect and print update report (read-only, zero files touched, zero git)
    cmUpdate,  # Local apply: modifies .nimble in-place, delegates lockfile to native solver, zero git
    cmCheck,   # Check mode: reports and exits with code 1 if updates found (for pre-commit/CI gating)
    cmCi       # CI/Action mode: automated GitOps branch creation, commits, push, and PR generation

proc printHelp() =
  echo """
renimble - Automated Dependency Updater for Nim & Nimble (v""" & RenimbleVersion & """)

Usage:
  renimble [command] [options]

Commands:
  (none) / report       Check for updates and display a formatted report (default, read-only)
  update / apply        Update .nimble and synchronize lockfiles in-place in working tree
  check                 Check for updates and exit with code 1 if any updates exist
  ci                    Run in automated CI mode (create branches, commit, push, and open PRs)

Options:
  -c, --config:<path>   Path to configuration file (default: .github/renimble.yml)
  -u, --update          Apply updates in-place in working tree (same as 'update' command)
  -k, --check           Exit with code 1 if updates found (same as 'check' command)
  -d, --dry-run         Force read-only report mode (same as 'report' command)
  --ci, -g, --git       Run in automated CI mode
  -v, --version         Print version information and exit
  -h, --help            Print this help message and exit
"""

proc findNimbleFile(dir: string): Option[string] =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble"):
      return some(path)
  return none(string)

proc resolveDefaultConfig(): string =
  if fileExists(".github/renimble.yml"):
    return ".github/renimble.yml"
  return ".github/renimble.yml"

proc main() =
  var configPath = resolveDefaultConfig()
  # Default mode: In CI default to cmCi, on developer machine default to cmReport
  var mode = if isGitHubActions(): cmCi else: cmReport

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key.toLowerAscii()
      of "h", "help":
        printHelp()
        quit(0)
      of "v", "version":
        echo "renimble " & RenimbleVersion
        quit(0)
      of "c", "config":
        configPath = p.val
      of "u", "update", "apply":
        mode = cmUpdate
      of "d", "dry-run", "report":
        mode = cmReport
      of "k", "check":
        mode = cmCheck
      of "g", "git", "ci":
        mode = cmCi
      else:
        echo "Unknown option: " & p.key
        quit(1)
    of cmdArgument:
      case p.key.toLowerAscii()
      of "update", "apply":
        mode = cmUpdate
      of "check", "outdated":
        mode = cmCheck
      of "report":
        mode = cmReport
      of "ci":
        mode = cmCi
      else:
        echo "Unknown command: " & p.key
        printHelp()
        quit(1)

  echo "==> Running renimble v" & RenimbleVersion & " (" & $mode & ")"
  let conf = loadConfig(configPath)
  echo "==> Loaded config with " & $conf.updates.len & " target(s)"

  var reg = newPackageRegistry()
  echo "==> Initializing Nimble package registry..."
  if reg.fetchRegistry():
    echo "==> Loaded " & $reg.packages.len & " packages from registry cache."
  else:
    echo "==> [WARN] Could not fetch remote registry, using local cache / offline mode."

  var totalUpdates = 0

  for target in conf.updates:
    let targetDir = if target.directory.startsWith("/"): target.directory[1..^1] else: target.directory
    let searchDir = if targetDir.len == 0: "." else: targetDir

    let nimbleFileOpt = findNimbleFile(searchDir)
    if nimbleFileOpt.isNone:
      echo "==> No .nimble file found in directory: " & searchDir
      continue

    let nimblePath = nimbleFileOpt.get
    echo "==> Analyzing manifest: " & nimblePath
    let nimbleContent = readFile(nimblePath)
    let manifest = parseNimbleManifest(nimbleContent, nimblePath)

    let lockPath = searchDir / "nimble.lock"
    var lockFileOpt: Option[LockFile] = none(LockFile)
    if fileExists(lockPath):
      echo "==> Found lockfile: " & lockPath
      let parsedLock = parseLockFile(readFile(lockPath), lockPath)
      let integrityIssues = validateLockIntegrity(manifest, parsedLock)
      for issue in integrityIssues:
        echo "==> [WARN] Lockfile integrity: " & issue
      lockFileOpt = some(parsedLock)

    let atlasConfigOpt = loadAtlasConfig(searchDir)
    if atlasConfigOpt.isSome:
      echo "==> Detected Atlas workspace configuration."

    let atlasLockPath = searchDir / "atlas.lock"
    var atlasLockOpt: Option[AtlasLock] = loadAtlasLock(atlasLockPath)
    if atlasLockOpt.isSome:
      echo "==> Found Atlas lockfile: " & atlasLockPath

    let dismissals = fetchClosedPrDismissals()
    if dismissals.len > 0:
      echo "==> Loaded " & $dismissals.len & " closed PR dismissal(s) to suppress duplicate notifications."

    echo "==> Checking " & $manifest.dependencies.len & " dependencies..."
    var updates: seq[UpdateProposal] = @[]
    for dep in manifest.dependencies:
      let propOpt = resolveDependencyUpdate(dep, target, reg, lockFileOpt, atlasConfigOpt, dismissals)
      if propOpt.isSome:
        updates.add(propOpt.get)

    if updates.len == 0:
      echo "==> All dependencies in " & nimblePath & " are up to date!"
      continue

    totalUpdates += updates.len
    echo "\n=== Available Updates (" & $updates.len & ") ==="
    for u in updates:
      let lockOnlyTag = if u.isLockfileOnly: " [lockfile-only]" else: ""
      echo "  • " & u.dependency.name & ": " & u.currentVersion & " -> " & u.targetVersion & " (" & $u.bumpType & ")" & lockOnlyTag
    echo "==============================\n"

    # -------------------------------------------------------------------------
    # Mode 1: Report Mode (Default local - read only)
    # -------------------------------------------------------------------------
    if mode == cmReport:
      echo "ℹ Run 'renimble update' to apply these updates in-place in your working tree."
      continue

    # -------------------------------------------------------------------------
    # Mode 2: Check Mode (CI / Pre-commit gate)
    # -------------------------------------------------------------------------
    if mode == cmCheck:
      continue

    # -------------------------------------------------------------------------
    # Mode 3 & 4: In-Place Update (cmUpdate) or Automated CI (cmCi)
    # -------------------------------------------------------------------------
    var updatedNimble = nimbleContent
    var modifiedFiles: seq[string] = @[]
    var nimbleModified = false
    var updatedPkgNames: seq[string] = @[]

    for u in updates:
      updatedPkgNames.add(cleanPackageName(u.dependency.name))
      if not u.isLockfileOnly:
        let newConstraint = updateConstraintString(u.dependency.rawConstraint, u.targetVersion)
        updatedNimble = rewriteNimbleFile(updatedNimble, u.dependency.name, newConstraint)
        nimbleModified = true

    if nimbleModified:
      writeFile(nimblePath, updatedNimble)
      echo "==> Updated " & nimblePath & " in-place."
      modifiedFiles.add(nimblePath)

    # Check if compiler version was updated and synchronize workflow / env files
    for u in updates:
      if u.dependency.name.toLowerAscii() == "nim":
        let targetNimVer = u.targetVersion
        # 1. Update .github/workflows/*.yml
        let wfDir = searchDir / ".github" / "workflows"
        if dirExists(wfDir):
          for kind, path in walkDir(wfDir):
            if kind == pcFile and (path.endsWith(".yml") or path.endsWith(".yaml")):
              let (newContent, modded) = updateWorkflowNimVersion(readFile(path), targetNimVer)
              if modded:
                writeFile(path, newContent)
                echo "==> Updated compiler version in workflow: " & path
                if path notin modifiedFiles: modifiedFiles.add(path)

        # 2. Update .tool-versions
        let tvPath = searchDir / ".tool-versions"
        if fileExists(tvPath):
          let (newTv, modded) = updateToolVersionsNim(readFile(tvPath), targetNimVer)
          if modded:
            writeFile(tvPath, newTv)
            echo "==> Updated compiler version in: " & tvPath
            if tvPath notin modifiedFiles: modifiedFiles.add(tvPath)

        # 3. Update .mise.toml
        let misePath = searchDir / ".mise.toml"
        if fileExists(misePath):
          let (newMise, modded) = updateMiseTomlNim(readFile(misePath), targetNimVer)
          if modded:
            writeFile(misePath, newMise)
            echo "==> Updated compiler version in: " & misePath
            if misePath notin modifiedFiles: modifiedFiles.add(misePath)

    # Re-resolve lockfiles via delegated native solver to avoid transitive graph corruption
    let isAtlas = atlasConfigOpt.isSome or atlasLockOpt.isSome
    let solverRes = runNativeLockfileSync(searchDir, updatedPkgNames, isAtlas)

    if solverRes.usedNativeSolver and solverRes.success:
      echo "==> [Solver] Re-resolved and verified lockfile via '" & solverRes.commandRan & "' (transitive graph intact)."
      if fileExists(lockPath) and lockPath notin modifiedFiles:
        modifiedFiles.add(lockPath)
      if fileExists(atlasLockPath) and atlasLockPath notin modifiedFiles:
        modifiedFiles.add(atlasLockPath)
    else:
      # If native solver is missing or failed, apply top-level updates and warn developer
      if lockFileOpt.isSome:
        var lock = lockFileOpt.get
        for u in updates:
          updateLockPackage(lock, u.dependency.name, u.targetVersion, u.targetVcsRevision)
        writeFile(lockPath, serializeLockFile(lock))
        echo "==> Updated " & lockPath & " (top-level only)."
        modifiedFiles.add(lockPath)

      if atlasLockOpt.isSome:
        var alock = atlasLockOpt.get
        for u in updates:
          updateAtlasLock(alock, cleanPackageName(u.dependency.name), u.targetVcsRevision, u.targetVersion)
        writeFile(atlasLockPath, serializeAtlasLock(alock))
        echo "==> Updated " & atlasLockPath & " (top-level only)."
        modifiedFiles.add(atlasLockPath)

      if solverRes.usedNativeSolver:
        echo "==> [WARN] Native solver output: " & solverRes.output.strip()
      else:
        echo "==> [Advisory] Native solver (nimble/atlas) not found in PATH. Run 'nimble lock' to verify transitive dependencies."

    # In local update mode (cmUpdate), we STOP HERE! Zero git operations.
    if mode == cmUpdate:
      echo "\n✔ Updates applied in working tree. Review changes with 'git diff' and run 'nimble test' to verify."
      continue

    # In CI mode (cmCi), proceed with automated branch creation, commit, and PR generation
    if mode == cmCi:
      echo "==> [GitOps] Creating branch and committing updates..."
      let report = executeGitOps(
        updates,
        modifiedFiles,
        baseBranch = target.targetBranch,
        authorName = "renimble[bot]",
        authorEmail = "renimble[bot]@users.noreply.github.com",
        workingDir = searchDir,
        commitPrefix = target.commitMessage.prefix
      )
      if report.success:
        echo "==> [GitOps] Successfully created branch '" & report.branchName & "' and committed changes."
        if isGitHubActions() and getEnv("RENIMBLE_NO_PUSH", "0") != "1":
          echo "==> [GitOps] Pushing branch to remote origin..."
          let pushRes = gitPush(report.branchName, "origin", workingDir = searchDir)
          if pushRes.success:
            echo "==> [GitOps] Branch pushed. Opening pull request..."
            let prRes = createPullRequest(
              report,
              baseBranch = target.targetBranch,
              labels = target.labels,
              reviewers = target.reviewers,
              assignees = target.assignees,
              workingDir = searchDir
            )
            if prRes.success:
              echo "==> [GitOps] Successfully opened PR: " & prRes.output
            else:
              echo "==> [WARN] Could not create PR: " & prRes.output
          else:
            echo "==> [WARN] Push failed: " & pushRes.output
        else:
          echo "==> [GitOps] Local execution or RENIMBLE_NO_PUSH active: branch created locally without pushing to remote."
      else:
        echo "==> [WARN] GitOps error: " & report.error

  if isGitHubActions():
    setActionOutput("updates_count", $totalUpdates)
    if totalUpdates > 0:
      setActionOutput("has_updates", "true")
    else:
      setActionOutput("has_updates", "false")

  if mode == cmCheck and totalUpdates > 0:
    quit(1)

when isMainModule:
  main()
