import std/[os, parseopt, strutils, options, tables]
import dependanim/[types, version, declarative_parser, rewriter, lockfile, config, registry, engine, pr, github_actions]

const DependanimVersion = "0.1.0"

proc printHelp() =
  echo """
dependanim - Automated Dependency Updater for Nim & Nimble (v""" & DependanimVersion & """)
Usage:
  dependanim [options]

Options:
  -c, --config:<path>   Path to configuration file (default: .github/dependanim.yml)
  -d, --dry-run         Check for updates without modifying files or opening PRs
  -k, --check           Check for updates and exit with code 1 if updates found
  -g, --git             Create git branch and commit changes for updates
  -v, --version         Print version information and exit
  -h, --help            Print this help message and exit
"""

proc findNimbleFile(dir: string): Option[string] =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble"):
      return some(path)
  return none(string)

proc main() =
  var configPath = ".github/dependanim.yml"
  var dryRun = false
  var checkOnly = false
  var enableGit = false

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
        echo "dependanim " & DependanimVersion
        quit(0)
      of "c", "config":
        configPath = p.val
      of "d", "dry-run":
        dryRun = true
      of "k", "check":
        checkOnly = true
      of "g", "git":
        enableGit = true
      else:
        echo "Unknown option: " & p.key
        quit(1)
    of cmdArgument:
      discard

  echo "==> Running dependanim v" & DependanimVersion
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

    echo "==> Checking " & $manifest.dependencies.len & " dependencies..."
    var updates: seq[UpdateProposal] = @[]
    for dep in manifest.dependencies:
      let propOpt = resolveDependencyUpdate(dep, target, reg, lockFileOpt)
      if propOpt.isSome:
        updates.add(propOpt.get)

    if updates.len == 0:
      echo "==> All dependencies in " & nimblePath & " are up to date!"
      continue

    totalUpdates += updates.len
    echo "\n=== Available Updates (" & $updates.len & ") ==="
    for u in updates:
      echo "  • " & u.dependency.name & ": " & u.currentVersion & " -> " & u.targetVersion & " (" & $u.bumpType & ")"
    echo "==============================\n"

    if dryRun or checkOnly:
      continue

    # Apply updates
    var updatedNimble = nimbleContent
    for u in updates:
      let newConstraint = updateConstraintString(u.dependency.rawConstraint, parseSemVersion(u.targetVersion))
      updatedNimble = rewriteNimbleFile(updatedNimble, u.dependency.name, newConstraint)

    writeFile(nimblePath, updatedNimble)
    echo "==> Updated " & nimblePath & " in-place."

    var modifiedFiles: seq[string] = @[nimblePath]
    if lockFileOpt.isSome:
      var lock = lockFileOpt.get
      for u in updates:
        updateLockPackage(lock, u.dependency.name, u.targetVersion, u.targetVcsRevision)
      writeFile(lockPath, serializeLockFile(lock))
      echo "==> Updated " & lockPath & " in-place."
      modifiedFiles.add(lockPath)

    if enableGit or isGitHubActions():
      echo "==> [GitOps] Creating branch and committing updates..."
      let report = executeGitOps(
        updates,
        modifiedFiles,
        baseBranch = target.targetBranch,
        authorName = "dependanim[bot]",
        authorEmail = "dependanim[bot]@users.noreply.github.com",
        workingDir = searchDir,
        commitPrefix = target.commitMessage.prefix
      )
      if report.success:
        echo "==> [GitOps] Successfully created branch '" & report.branchName & "' and committed changes."
      else:
        echo "==> [WARN] GitOps error: " & report.error

  if isGitHubActions():
    setActionOutput("updates_count", $totalUpdates)
    if totalUpdates > 0:
      setActionOutput("has_updates", "true")
    else:
      setActionOutput("has_updates", "false")

  if checkOnly and totalUpdates > 0:
    quit(1)

when isMainModule:
  main()
