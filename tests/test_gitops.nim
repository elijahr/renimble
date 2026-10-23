import unittest, std/[os, strutils, options]
import ../src/renimble/[types, pr]

suite "Git Operations & PR Engine":
  test "runGit checks git version":
    let res = runGit(["version"])
    check res.success
    check res.exitCode == 0
    check "git version" in res.output

  test "generateBranchName":
    let p1 = UpdateProposal(
      dependency: Dependency(name: "zippy"),
      currentVersion: "0.10.4",
      targetVersion: "0.11.0",
      bumpType: btMinor
    )
    check generateBranchName(@[p1]) == "renimble/zippy-0.11.0"
    check generateBranchName(@[p1], some("core")) == "renimble/group-core"

    let p2 = UpdateProposal(
      dependency: Dependency(name: "yaml"),
      currentVersion: "1.0.0",
      targetVersion: "1.1.0",
      bumpType: btMinor
    )
    check generateBranchName(@[p1, p2]) == "renimble/updates"

  test "generateCommitMessage":
    let p1 = UpdateProposal(
      dependency: Dependency(name: "zippy"),
      currentVersion: "0.10.4",
      targetVersion: "0.11.0",
      bumpType: btMinor
    )
    let msg1 = generateCommitMessage(@[p1], "chore(deps)")
    check msg1 == "chore(deps): bump zippy from 0.10.4 to 0.11.0"

    let p2 = UpdateProposal(
      dependency: Dependency(name: "yaml"),
      currentVersion: "1.0.0",
      targetVersion: "1.1.0",
      bumpType: btMinor
    )
    let msg2 = generateCommitMessage(@[p1, p2], "fix(deps)")
    check "fix(deps): bump 2 dependencies" in msg2
    check "- zippy from 0.10.4 to 0.11.0" in msg2
    check "- yaml from 1.0.0 to 1.1.0" in msg2

  test "generatePrTitle & generatePrBody":
    let p1 = UpdateProposal(
      dependency: Dependency(name: "zippy"),
      currentVersion: "0.10.4",
      targetVersion: "0.11.0",
      bumpType: btMinor,
      changelogUrl: some("https://github.com/guzba/zippy/releases")
    )
    let title = generatePrTitle(@[p1])
    check title == "chore(deps): bump zippy from 0.10.4 to 0.11.0"

    let body = generatePrBody(@[p1])
    check "| `zippy` | `0.10.4` | `0.11.0` | Minor | [Changelog](https://github.com/guzba/zippy/releases) |" in body
    check "@renimble rebase" in body

  test "Isolated local GitOps workflow in temp git repository":
    let tmpDir = getTempDir() / "renimble_gitops_test_" & $getCurrentProcessId()
    createDir(tmpDir)

    try:
      # Initialize git repo
      let initRes = runGit(["init", "-b", "main"], tmpDir)
      if not initRes.success:
        # Fallback for older git versions
        discard runGit(["init"], tmpDir)
        discard runGit(["checkout", "-b", "main"], tmpDir)

      discard runGit(["config", "user.name", "Test Runner"], tmpDir)
      discard runGit(["config", "user.email", "test@example.com"], tmpDir)

      # Create initial commit
      let initialFile = tmpDir / "test.txt"
      writeFile(initialFile, "Initial content\n")
      let stageInit = gitStageFiles(@["test.txt"], tmpDir)
      check stageInit.success
      let commitInit = gitCommit("Initial commit", "Test Runner", "test@example.com", tmpDir)
      check commitInit.success

      # Verify clean status
      check not gitIsDirty(tmpDir)

      # Test branch creation
      let branchRes = gitCreateBranch("test-branch", "main", tmpDir)
      check branchRes.success
      check gitCurrentBranch(tmpDir) == "test-branch"
      check gitBranchExists("test-branch", tmpDir)

      # Test modifications and staging
      writeFile(tmpDir / "app.nimble", "version = \"0.1.0\"\nrequires \"zippy >= 0.10.4\"\n")
      check gitIsDirty(tmpDir)

      # Test executeGitOps
      let proposal = UpdateProposal(
        dependency: Dependency(name: "zippy"),
        currentVersion: "0.10.4",
        targetVersion: "0.11.0",
        bumpType: btMinor
      )
      
      let opsReport = executeGitOps(
        proposals = @[proposal],
        modifiedFiles = @["app.nimble"],
        baseBranch = "main",
        workingDir = tmpDir
      )

      check opsReport.success
      check opsReport.branchName == "renimble/zippy-0.11.0"
      check gitCurrentBranch(tmpDir) == "renimble/zippy-0.11.0"
      check not gitIsDirty(tmpDir)

      # Verify commit message in git log
      let logRes = runGit(["log", "-1", "--pretty=%B"], tmpDir)
      check logRes.success
      check "chore(deps): bump zippy from 0.10.4 to 0.11.0" in logRes.output

    finally:
      removeDir(tmpDir)
