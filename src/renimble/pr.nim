import std/[strutils, options, osproc, streams, json]
import types

type
  GitCommandResult* = object
    success*: bool
    exitCode*: int
    output*: string
    command*: string

  GitOpsReport* = object
    branchName*: string
    commitMessage*: string
    prTitle*: string
    prBody*: string
    stagedFiles*: seq[string]
    success*: bool
    error*: string

proc cleanPkgName(name: string): string =
  if name.startsWith("http://") or name.startsWith("https://") or name.startsWith("git://") or name.startsWith("git@"):
    var clean = name
    if clean.endsWith(".git"):
      clean = clean[0..^5]
    let lastSlash = clean.rfind('/')
    if lastSlash != -1:
      return clean[(lastSlash + 1)..^1]
    return clean
  return name

proc generateBranchName*(proposals: seq[UpdateProposal], groupName: Option[string] = none(string)): string =
  if groupName.isSome:
    return "renimble/group-" & groupName.get
  elif proposals.len == 1:
    let p = proposals[0]
    return "renimble/" & cleanPkgName(p.dependency.name) & "-" & p.targetVersion
  else:
    return "renimble/updates"

proc generateCommitMessage*(proposals: seq[UpdateProposal], prefix: string = "chore(deps)"): string =
  if proposals.len == 1:
    let p = proposals[0]
    return prefix & ": bump " & p.dependency.name & " from " & p.currentVersion & " to " & p.targetVersion
  else:
    var msg = prefix & ": bump " & $proposals.len & " dependencies\n\n"
    for p in proposals:
      msg.add("- " & p.dependency.name & " from " & p.currentVersion & " to " & p.targetVersion & "\n")
    return msg.strip()

proc generatePrTitle*(proposals: seq[UpdateProposal], groupName: Option[string] = none(string)): string =
  if groupName.isSome:
    return "chore(deps): update " & groupName.get & " group (" & $proposals.len & " packages)"
  elif proposals.len == 1:
    let p = proposals[0]
    return "chore(deps): bump " & p.dependency.name & " from " & p.currentVersion & " to " & p.targetVersion
  else:
    return "chore(deps): bump " & $proposals.len & " dependencies"

proc generatePrBody*(proposals: seq[UpdateProposal]): string =
  result = "Bumps dependencies using **[renimble](https://github.com/axiomantic/renimble)**.\n\n"
  result.add("### Updates\n\n")
  result.add("| Package | From | To | Type | Links |\n")
  result.add("|:---|:---|:---|:---|:---|\n")

  for p in proposals:
    let bumpStr = case p.bumpType
      of btMajor: "**Major**"
      of btMinor: "Minor"
      of btPatch: "Patch"
      of btVcs: "VCS Pin"
      of btNone: "None"

    let cl = if p.changelogUrl.isSome: "[Changelog](" & p.changelogUrl.get & ")" else: "-"
    result.add("| `" & p.dependency.name & "` | `" & p.currentVersion & "` | `" & p.targetVersion & "` | " & bumpStr & " | " & cl & " |\n")

  result.add("\n---\n")
  result.add("<details>\n<summary>Renimble Commands & Options</summary>\n\n")
  result.add("You can trigger Renimble actions by commenting on this PR:\n")
  result.add("- `@renimble rebase` will rebase this branch against the target branch\n")
  result.add("- `@renimble recreate` will recreate this PR and recalculate constraints\n")
  result.add("- `@renimble close` will close this PR and ignore this version bump\n")
  result.add("</details>\n")

  # Append hidden metadata HTML comment for closed PR tracking & dismissal recovery
  result.add("\n<!-- renimble-metadata\n")
  var jMeta = newJObject()
  var jProposals = newJArray()
  for p in proposals:
    var jP = newJObject()
    jP["package"] = %cleanPkgName(p.dependency.name)
    jP["currentVersion"] = %p.currentVersion
    jP["targetVersion"] = %p.targetVersion
    jP["targetVcsRevision"] = %p.targetVcsRevision
    jP["bumpType"] = %($p.bumpType)
    jProposals.add(jP)
  jMeta["proposals"] = jProposals
  result.add(pretty(jMeta, indent = 2) & "\n-->\n")

# ==============================================================================
# Git Operations Engine
# ==============================================================================

proc runGit*(args: openArray[string], workingDir: string = ""): GitCommandResult =
  ## Runs a git process with given arguments in workingDir.
  try:
    let p = startProcess(
      command = "git",
      workingDir = workingDir,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
    let output = p.outputStream.readAll()
    let exitCode = p.waitForExit()
    p.close()
    return GitCommandResult(
      success: exitCode == 0,
      exitCode: exitCode,
      output: output.strip(),
      command: "git " & args.join(" ")
    )
  except CatchableError as e:
    return GitCommandResult(
      success: false,
      exitCode: -1,
      output: e.msg,
      command: "git " & args.join(" ")
    )

proc gitCurrentBranch*(workingDir: string = ""): string =
  ## Returns the current branch name or empty string if not in a branch.
  let res = runGit(["rev-parse", "--abbrev-ref", "HEAD"], workingDir)
  if res.success:
    return res.output
  return ""

proc gitBranchExists*(branchName: string, workingDir: string = ""): bool =
  ## Returns true if branchName exists locally.
  let res = runGit(["show-ref", "--verify", "--quiet", "refs/heads/" & branchName], workingDir)
  return res.success

proc gitCheckoutBranch*(branchName: string, create: bool = false, baseBranch: string = "", workingDir: string = ""): GitCommandResult =
  ## Checks out a branch, optionally creating / resetting it from baseBranch.
  if create:
    if baseBranch.len > 0:
      return runGit(["checkout", "-B", branchName, baseBranch], workingDir)
    else:
      return runGit(["checkout", "-B", branchName], workingDir)
  else:
    return runGit(["checkout", branchName], workingDir)

proc gitCreateBranch*(branchName: string, baseBranch: string = "", workingDir: string = ""): GitCommandResult =
  ## Convenience helper to create and checkout branch from baseBranch.
  return gitCheckoutBranch(branchName, create = true, baseBranch = baseBranch, workingDir = workingDir)

proc gitStageFiles*(files: openArray[string], workingDir: string = ""): GitCommandResult =
  ## Stages the given files with git add.
  if files.len == 0:
    return GitCommandResult(success: true, exitCode: 0, output: "", command: "git add")
  var args: seq[string] = @["add", "--"]
  for f in files:
    args.add(f)
  return runGit(args, workingDir)

proc gitCommit*(message: string, authorName: string = "renimble[bot]", authorEmail: string = "renimble[bot]@users.noreply.github.com", workingDir: string = ""): GitCommandResult =
  ## Commits staged changes with custom author info.
  let args = @[
    "-c", "user.name=" & authorName,
    "-c", "user.email=" & authorEmail,
    "commit", "-m", message
  ]
  return runGit(args, workingDir)

proc gitStatusPorcelain*(workingDir: string = ""): string =
  ## Returns raw porcelain status output.
  let res = runGit(["status", "--porcelain"], workingDir)
  return res.output

proc gitIsDirty*(workingDir: string = ""): bool =
  ## Returns true if the git worktree has uncommitted modifications.
  return gitStatusPorcelain(workingDir).len > 0

proc gitPush*(branchName: string, remote: string = "origin", force: bool = false, workingDir: string = ""): GitCommandResult =
  ## Pushes the branch to remote.
  var args: seq[string] = @["push"]
  if force:
    args.add("--force")
  args.add("-u")
  args.add(remote)
  args.add(branchName)
  return runGit(args, workingDir)

proc executeGitOps*(
  proposals: seq[UpdateProposal],
  modifiedFiles: seq[string],
  baseBranch: string = "main",
  groupName: Option[string] = none(string),
  authorName: string = "renimble[bot]",
  authorEmail: string = "renimble[bot]@users.noreply.github.com",
  workingDir: string = "",
  commitPrefix: string = "chore(deps)"
): GitOpsReport =
  ## Orchestrates branch creation, file staging, and commit generation.
  let branchName = generateBranchName(proposals, groupName)
  let commitMessage = generateCommitMessage(proposals, commitPrefix)
  let prTitle = generatePrTitle(proposals, groupName)
  let prBody = generatePrBody(proposals)

  result = GitOpsReport(
    branchName: branchName,
    commitMessage: commitMessage,
    prTitle: prTitle,
    prBody: prBody,
    stagedFiles: @modifiedFiles,
    success: false,
    error: ""
  )

  # 1. Create and switch to new branch
  let branchRes = gitCreateBranch(branchName, baseBranch, workingDir)
  if not branchRes.success:
    result.error = "Failed to create branch '" & branchName & "': " & branchRes.output
    return result

  # 2. Stage modified files
  let stageRes = gitStageFiles(modifiedFiles, workingDir)
  if not stageRes.success:
    result.error = "Failed to stage files: " & stageRes.output
    return result

  # 3. Commit changes
  let commitRes = gitCommit(commitMessage, authorName, authorEmail, workingDir)
  if not commitRes.success:
    result.error = "Failed to commit changes: " & commitRes.output
    return result

  result.success = true
