import std/[unittest, tables, os, strutils, json]
import ../src/renimble/[types, version, dismissal, atlas, declarative_parser, rewriter, compiler, pr, solver]

suite "Advanced Dependency Engine Features":

  # ---------------------------------------------------------------------------
  # 1. Inequality Operator (!=)
  # ---------------------------------------------------------------------------
  test "Parse and evaluate != operator":
    let c = parseSingleConstraint("!= 1.5.0")
    check c.op == voNe
    check c.spec.semver == parseSemVersion("1.5.0")

    check parseSemVersion("1.4.0").satisfiesSingle(c)
    check parseSemVersion("1.6.0").satisfiesSingle(c)
    check not parseSemVersion("1.5.0").satisfiesSingle(c)

    let comp = parseVersionConstraint(">= 1.0.0 & <= 2.0.0 & != 1.5.0")
    check comp.constraints.len == 3
    check parseSemVersion("1.2.0").satisfies(comp)
    check not parseSemVersion("1.5.0").satisfies(comp)
    check not parseSemVersion("2.1.0").satisfies(comp)

  # ---------------------------------------------------------------------------
  # 2. URL Package Dependencies & Name Cleaning
  # ---------------------------------------------------------------------------
  test "Clean package names from direct Git / HTTPS URLs":
    check cleanPackageName("zippy") == "zippy"
    check cleanPackageName("https://github.com/nim-lang/zip") == "zip"
    check cleanPackageName("https://github.com/nim-lang/zip.git") == "zip"
    check cleanPackageName("git@github.com:tree-sitter/nim-tree-sitter.git") == "nim-tree-sitter"

  test "Parse direct URL requires statements":
    let src = """
requires "https://github.com/nim-lang/zip >= 0.3.1"
"""
    let manifest = parseNimbleManifest(src)
    check manifest.dependencies.len == 1
    let dep = manifest.dependencies[0]
    check dep.name == "https://github.com/nim-lang/zip"
    check cleanPackageName(dep.name) == "zip"
    check dep.constraint.constraints.len == 1
    check dep.constraint.constraints[0].op == voGe
    check dep.constraint.constraints[0].spec.semver == parseSemVersion("0.3.1")

  # ---------------------------------------------------------------------------
  # 3. Commit Hash Pin Updating
  # ---------------------------------------------------------------------------
  test "Update commit hash pins in constraint string":
    let oldConstraint = "#a1b2c3d4e5f67890123456789012345678901234"
    let newSha = "1234567890abcdef1234567890abcdef12345678"
    let updated = updateConstraintString(oldConstraint, newSha)
    check updated == "#1234567890abcdef1234567890abcdef12345678"

    let manifestSrc = """requires "zippy#a1b2c3d4e5f67890123456789012345678901234""""
    let rewritten = rewriteNimbleFile(manifestSrc, "zippy", updated)
    check rewritten == """requires "zippy#1234567890abcdef1234567890abcdef12345678""""

  # ---------------------------------------------------------------------------
  # 4. Closed PR Dismissal Memory ("Ok I won't notify you again")
  # ---------------------------------------------------------------------------
  test "Parse gh closed PRs and detect unmerged dismissals":
    let sampleGhJson = """
[
  {
    "headRefName": "renimble/zippy-0.11.0",
    "mergedAt": null
  },
  {
    "headRefName": "renimble/yaml-2.1.0",
    "mergedAt": "2026-10-20T12:00:00Z"
  },
  {
    "headRefName": "renimble/chronos-4.0.0",
    "mergedAt": ""
  }
]
"""
    let dismissed = parseGhClosedPrs(sampleGhJson)
    check "renimble/zippy-0.11.0" in dismissed
    check "renimble/chronos-4.0.0" in dismissed
    # Merged PRs are not dismissed!
    check "renimble/yaml-2.1.0" notin dismissed

    check isVersionDismissed("zippy", "0.11.0", dismissed)
    check not isVersionDismissed("zippy", "0.12.0", dismissed)
    check not isVersionDismissed("yaml", "2.1.0", dismissed)

  test "Local dismissal persistence":
    let tmpDir = getTempDir() / "renimble_dismissal_test_" & $getCurrentProcessId()
    createDir(tmpDir)
    try:
      recordLocalDismissal("renimble/cligen-1.5.0", tmpDir)
      let loaded = loadLocalDismissals(tmpDir)
      check "renimble/cligen-1.5.0" in loaded
      check isVersionDismissed("cligen", "1.5.0", loaded)
    finally:
      removeDir(tmpDir)

  # ---------------------------------------------------------------------------
  # 5. Atlas Workspace Support (atlas.config and atlas.lock)
  # ---------------------------------------------------------------------------
  test "Parse atlas.config JSON with deps and nameOverrides":
    let sampleConfig = """
{
  "deps": "custom_deps",
  "nameOverrides": {
    "myfork": "https://github.com/myorg/myfork.git",
    "zippy": "https://github.com/myorg/custom-zippy.git"
  }
}
"""
    let cfg = parseAtlasConfig(sampleConfig)
    check cfg.deps == "custom_deps"
    check cfg.nameOverrides.hasKey("zippy")
    check cfg.nameOverrides["zippy"] == "https://github.com/myorg/custom-zippy.git"
    check cfg.nameOverrides["myfork"] == "https://github.com/myorg/myfork.git"

  test "Parse, update, and serialize atlas.lock":
    let sampleLock = """
{
  "zippy": {
    "url": "https://github.com/guzba/zippy",
    "commit": "a1b2c3d4",
    "version": "0.10.4"
  }
}
"""
    var lock = parseAtlasLock(sampleLock)
    check lock.packages.hasKey("zippy")
    check lock.packages["zippy"].commit == "a1b2c3d4"

    updateAtlasLock(lock, "zippy", "e5f6g7h8", "0.11.0")
    check lock.packages["zippy"].commit == "e5f6g7h8"
    check lock.packages["zippy"].version == "0.11.0"

    let serialized = serializeAtlasLock(lock)
    let reParsed = parseAtlasLock(serialized)
    check reParsed.packages["zippy"].commit == "e5f6g7h8"
    check reParsed.packages["zippy"].version == "0.11.0"

  # ---------------------------------------------------------------------------
  # 6. Hidden PR Metadata Extraction (Renovate Pattern)
  # ---------------------------------------------------------------------------
  test "Extract metadata from hidden HTML comment in PR body":
    let p = UpdateProposal(
      dependency: Dependency(name: "zippy"),
      currentVersion: "0.10.4",
      targetVersion: "0.11.0",
      targetVcsRevision: "abcdef123456",
      bumpType: btMinor
    )
    let body = generatePrBody(@[p])
    check "<!-- renimble-metadata" in body

    let extracted = extractMetadataFromPrBody(body)
    check "zippy:0.11.0" in extracted
    check "renimble/zippy-0.11.0" in extracted

    var jGh = newJArray()
    var jPr = newJObject()
    jPr["headRefName"] = %"renimble/group-core"
    jPr["mergedAt"] = newJNull()
    jPr["body"] = %body
    jGh.add(jPr)

    let dismissedFromGh = parseGhClosedPrs($jGh)
    check "zippy:0.11.0" in dismissedFromGh
    check isVersionDismissed("zippy", "0.11.0", dismissedFromGh)

  # ---------------------------------------------------------------------------
  # 7. Nim Compiler Version Updaters (Workflows, asdf, mise)
  # ---------------------------------------------------------------------------
  test "Update workflow nim-version step":
    let wf = """    steps:
      - uses: jiro4989/setup-nim-action@v2
        with:
          nim-version: '2.0.8'"""
    let expectedWf = """    steps:
      - uses: jiro4989/setup-nim-action@v2
        with:
          nim-version: '2.2.0'"""
    let (updatedWf, mod1) = updateWorkflowNimVersion(wf, "2.2.0")
    check mod1
    check updatedWf == expectedWf

    # Negative control: Already at target version
    let (sameWf, modSame) = updateWorkflowNimVersion(expectedWf, "2.2.0")
    check not modSame
    check sameWf == expectedWf

    # Negative control: Workflow without nim-version
    let nonNimWf = """    steps:
      - uses: actions/checkout@v4"""
    let (unmodWf, modNon) = updateWorkflowNimVersion(nonNimWf, "2.2.0")
    check not modNon
    check unmodWf == nonNimWf

  test "Update .tool-versions and .mise.toml":
    let tv = "nim 2.0.8\nnodejs 20.0.0\n"
    let (updatedTv, mod2) = updateToolVersionsNim(tv, "2.2.0")
    check mod2
    check updatedTv == "nim 2.2.0\nnodejs 20.0.0\n"

    # Negative control: tool-versions without nim
    let tvOther = "ruby 3.2.0\nnodejs 20.0.0\n"
    let (unmodTv, modTvOther) = updateToolVersionsNim(tvOther, "2.2.0")
    check not modTvOther
    check unmodTv == tvOther

    let mise = "[tools]\nnim = \"2.0.8\"\n"
    let (updatedMise, mod3) = updateMiseTomlNim(mise, "2.2.0")
    check mod3
    check updatedMise == "[tools]\nnim = \"2.2.0\"\n"

    # Negative control: mise.toml without nim
    let miseOther = "[tools]\npython = \"3.11\"\n"
    let (unmodMise, modMiseOther) = updateMiseTomlNim(miseOther, "2.2.0")
    check not modMiseOther
    check unmodMise == miseOther

  # ---------------------------------------------------------------------------
  # 8. Delegated Native Solver for Transitive Graph Verification
  # ---------------------------------------------------------------------------
  test "Check command availability detection":
    check isCommandAvailable("nim")
    check not isCommandAvailable("nonexistent_binary_tool_xyz987")

  test "Solver handles missing or failing solver cleanly without crash":
    let res = runNativeLockfileSync(
      workingDir = getTempDir(),
      packageNames = @["zippy"],
      isAtlas = false
    )
    # The call must return a structured result without throwing an unhandled exception
    check res.commandRan.len > 0

  # ---------------------------------------------------------------------------
  # 9. Pull Request Creation Engine & Dry-Run Command Generation
  # ---------------------------------------------------------------------------
  test "createPullRequest constructs proper command invocation":
    let r = GitOpsReport(
      branchName: "renimble/zippy-0.11.0",
      prTitle: "chore(deps): bump zippy from 0.10.4 to 0.11.0",
      prBody: "Automated bump body"
    )
    # Testing invocation in non-gh temp directory returns structured failure without crashing
    let prRes = createPullRequest(
      r,
      baseBranch = "main",
      labels = @["dependencies", "nim"],
      reviewers = @["alice"],
      assignees = @["bob"],
      workingDir = getTempDir()
    )
    check prRes.command.contains("pr create")
    check prRes.command.contains("--base main")
    check prRes.command.contains("--head renimble/zippy-0.11.0")
    check prRes.command.contains("--label dependencies")
    check prRes.command.contains("--label nim")
    check prRes.command.contains("--reviewer alice")
    check prRes.command.contains("--assignee bob")
