import std/[unittest, tables, strutils, options]
import
  ../src/renimble/[types, version, declarative_parser, rewriter, lockfile, upstream]

suite "Adversarial Testing Suite & Negative Controls":
  # ---------------------------------------------------------------------------
  # Pillar 1: Malformed SemVer Strings & Invalid Constraint Operators
  # ---------------------------------------------------------------------------

  test "Negative Control: Reject malformed SemVer strings":
    # Non-numeric strings must raise ValueError
    expect(ValueError):
      discard parseSemVersion("invalid.version")

    expect(ValueError):
      discard parseSemVersion("1.two.three")

    expect(ValueError):
      discard parseSemVersion("alpha.1.2")

    expect(ValueError):
      discard parseSemVersion("1..0")

    expect(ValueError):
      discard parseSemVersion("v1.0.invalid-number")

  test "Negative Control: Reject invalid constraint operators":
    # Unsupported or corrupted operators must raise ValueError
    expect(ValueError):
      discard parseSingleConstraint("! = 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint("=== 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint(">> 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint("<< 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint("? = 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint("~> 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint("^ 1.0.0")

    expect(ValueError):
      discard parseSingleConstraint("~ 1.0.0")

  test "Negative Control: SemVer precedence and negative comparison controls":
    let v1 = parseSemVersion("1.0.0")
    let v1_rc1 = parseSemVersion("1.0.0-rc.1")
    let v1_rc2 = parseSemVersion("1.0.0-rc.2")
    let v1_beta2 = parseSemVersion("1.0.0-beta.2")
    let v1_beta11 = parseSemVersion("1.0.0-beta.11")
    let v2 = parseSemVersion("2.0.0")

    # Strict precedence controls
    check (v1 < v2) == true
    check (v2 < v1) == false
    check (v1_rc1 < v1) == true
    check (v1 < v1_rc1) == false
    check (v1_rc1 < v1_rc2) == true
    check (v1_beta2 < v1_beta11) == true
    check (v1_rc2 == v1_rc2) == true
    check (v1 == v1_rc1) == false

  test "Negative Control: Strict constraint boundaries (^=, ~=, and unsatisfiable intersections)":
    # Caret ^= 0.2.3 (must lock to 0.2.x since major is 0)
    let cCaret02 = parseSingleConstraint("^= 0.2.3")
    check satisfiesSingle(parseSemVersion("0.2.3"), cCaret02) == true
    check satisfiesSingle(parseSemVersion("0.2.9"), cCaret02) == true
    check satisfiesSingle(parseSemVersion("0.3.0"), cCaret02) == false
    check satisfiesSingle(parseSemVersion("0.2.2"), cCaret02) == false
    check satisfiesSingle(parseSemVersion("1.0.0"), cCaret02) == false

    # Caret ^= 0.0.4 (must lock to exact 0.0.4 since major and minor are 0)
    let cCaret004 = parseSingleConstraint("^= 0.0.4")
    check satisfiesSingle(parseSemVersion("0.0.4"), cCaret004) == true
    check satisfiesSingle(parseSemVersion("0.0.5"), cCaret004) == false
    check satisfiesSingle(parseSemVersion("0.1.0"), cCaret004) == false

    # Tilde ~= 1.2.3 (patch-level changes only)
    let cTilde = parseSingleConstraint("~= 1.2.3")
    check satisfiesSingle(parseSemVersion("1.2.3"), cTilde) == true
    check satisfiesSingle(parseSemVersion("1.2.8"), cTilde) == true
    check satisfiesSingle(parseSemVersion("1.3.0"), cTilde) == false
    check satisfiesSingle(parseSemVersion("1.2.2"), cTilde) == false
    check satisfiesSingle(parseSemVersion("2.0.0"), cTilde) == false

    # Unsatisfiable intersected constraint: >= 2.0.0 & <= 1.0.0
    let cImpossible = parseVersionConstraint(">= 2.0.0 & <= 1.0.0")
    check satisfies(parseSemVersion("0.9.0"), cImpossible) == false
    check satisfies(parseSemVersion("1.0.0"), cImpossible) == false
    check satisfies(parseSemVersion("1.5.0"), cImpossible) == false
    check satisfies(parseSemVersion("2.0.0"), cImpossible) == false
    check satisfies(parseSemVersion("2.5.0"), cImpossible) == false

  # ---------------------------------------------------------------------------
  # Pillar 2: Preserving Tabs vs 2-Space vs 4-Space Indentation & Substring Collisions
  # ---------------------------------------------------------------------------

  test "Preserve exact 2-space indentation byte-for-byte":
    let original = [
      "# Package Manifest", "version = \"1.0.0\"", "", "# Dependencies",
      "  requires \"nim >= 2.0.0\"",
      "  requires \"zippy >= 0.10.4\"  # trailing comment",
      "  requires \"yaml >= 2.1.0\"", "", "task build, \"Build\":",
      "  exec \"nim c src/main.nim\"",
    ].join("\n")

    let expected = [
      "# Package Manifest", "version = \"1.0.0\"", "", "# Dependencies",
      "  requires \"nim >= 2.0.0\"",
      "  requires \"zippy >= 0.11.0\"  # trailing comment",
      "  requires \"yaml >= 2.1.0\"", "", "task build, \"Build\":",
      "  exec \"nim c src/main.nim\"",
    ].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

  test "Preserve exact 4-space indentation byte-for-byte":
    let original = [
      "    requires \"nim >= 2.0.0\"", "    requires \"zippy >= 0.10.4\"",
      "    requires \"yaml >= 2.1.0\"",
    ].join("\n")

    let expected = [
      "    requires \"nim >= 2.0.0\"", "    requires \"zippy >= 0.11.0\"",
      "    requires \"yaml >= 2.1.0\"",
    ].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

  test "Preserve exact tab indentation byte-for-byte":
    let original = [
      "\trequires \"nim >= 2.0.0\"", "\trequires \"zippy >= 0.10.4\"\t# tabbed comment",
      "\trequires \"yaml >= 2.1.0\"",
    ].join("\n")

    let expected = [
      "\trequires \"nim >= 2.0.0\"", "\trequires \"zippy >= 0.11.0\"\t# tabbed comment",
      "\trequires \"yaml >= 2.1.0\"",
    ].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

  test "Negative Control: Package name substring collision immunity":
    # zippy must not match zip, zippy_utils, or libzip
    let original = [
      "requires \"zip >= 1.0.0\"", "requires \"zippy >= 0.10.4\"",
      "requires \"zippy_utils >= 2.0.0\"", "requires \"libzip >= 3.0.0\"",
    ].join("\n")

    let expectedZippyUpdate = [
      "requires \"zip >= 1.0.0\"", "requires \"zippy >= 0.11.0\"",
      "requires \"zippy_utils >= 2.0.0\"", "requires \"libzip >= 3.0.0\"",
    ].join("\n")

    let actualZippy = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actualZippy == expectedZippyUpdate

    # Rewriting 'zip' must not affect 'zippy', 'zippy_utils', or 'libzip'
    let expectedZipUpdate = [
      "requires \"zip >= 1.2.0\"", "requires \"zippy >= 0.10.4\"",
      "requires \"zippy_utils >= 2.0.0\"", "requires \"libzip >= 3.0.0\"",
    ].join("\n")

    let actualZip = rewriteNimbleFile(original, "zip", ">= 1.2.0")
    check actualZip == expectedZipUpdate

  test "Preserve multi-package comma declarations with inline spacing":
    let original = "requires \"nim >= 2.0.0\", \"zippy >= 0.10.4\", \"yaml >= 2.1.0\""
    let expected = "requires \"nim >= 2.0.0\", \"zippy >= 0.11.0\", \"yaml >= 2.1.0\""
    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

  # ---------------------------------------------------------------------------
  # Pillar 3: Non-standard Task Blocks, Nested Quotes & Multiline Strings
  # ---------------------------------------------------------------------------

  test "Negative Control: Task blocks with nested quotes, CLI flags, and echo statements":
    let original = [
      "version = \"0.1.0\"", "author  = \"Axiomantic\"", "",
      "requires \"zippy >= 0.10.4\"", "",
      "task test, \"Run tests with nested options\":",
      "  exec \"nim c -r --define:pkg=\\\"zippy\\\" tests/test_all.nim\"",
      "  echo \"Task completed: requires zippy >= 0.10.4\"", "",
      "task deploy, \"Production deploy\":", "  exec \"echo deploying\"",
    ].join("\n")

    let expected = [
      "version = \"0.1.0\"", "author  = \"Axiomantic\"", "",
      "requires \"zippy >= 0.11.0\"", "",
      "task test, \"Run tests with nested options\":",
      "  exec \"nim c -r --define:pkg=\\\"zippy\\\" tests/test_all.nim\"",
      "  echo \"Task completed: requires zippy >= 0.10.4\"", "",
      "task deploy, \"Production deploy\":", "  exec \"echo deploying\"",
    ].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

    # Verify manifest parser also ignores requires inside task echo or comments
    let manifest = parseNimbleManifest(original)
    check manifest.dependencies.len == 1
    check manifest.dependencies[0].name == "zippy"
    check manifest.dependencies[0].rawConstraint == ">= 0.10.4"

  test "Negative Control: Multiline triple-quoted docstrings inside task blocks":
    let original = [
      "requires \"zippy >= 0.10.4\"", "", "task docgen, \"\"\"",
      "Documentation generator task.", "Usage:",
      "  requires \"zippy >= 0.10.4\" in user docs", "\"\"\":",
      "  exec \"nim doc src/renimble.nim\"",
    ].join("\n")

    let expected = [
      "requires \"zippy >= 0.11.0\"", "", "task docgen, \"\"\"",
      "Documentation generator task.", "Usage:",
      "  requires \"zippy >= 0.10.4\" in user docs", "\"\"\":",
      "  exec \"nim doc src/renimble.nim\"",
    ].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

    let manifest = parseNimbleManifest(original)
    check manifest.dependencies.len == 1
    check manifest.dependencies[0].name == "zippy"

  test "Negative Control: Identifiers and task names with 'requires' prefix":
    let original = [
      "requires_helper = \"zippy\"", "requires \"zippy >= 0.10.4\"", "",
      "task requires_audit, \"Audit all requirements\":",
      "  let requires_file = \"nimble.lock\"", "  echo requires_file",
    ].join("\n")

    let expected = [
      "requires_helper = \"zippy\"", "requires \"zippy >= 0.11.0\"", "",
      "task requires_audit, \"Audit all requirements\":",
      "  let requires_file = \"nimble.lock\"", "  echo requires_file",
    ].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

    let manifest = parseNimbleManifest(original)
    check manifest.dependencies.len == 1
    check manifest.dependencies[0].name == "zippy"

  test "Negative Control: Commented-out requires lines must remain untouched":
    let original =
      ["# requires \"zippy >= 0.9.0\"", "requires \"zippy >= 0.10.4\""].join("\n")

    let expected =
      ["# requires \"zippy >= 0.9.0\"", "requires \"zippy >= 0.11.0\""].join("\n")

    let actual = rewriteNimbleFile(original, "zippy", ">= 0.11.0")
    check actual == expected

    let manifest = parseNimbleManifest(original)
    check manifest.dependencies.len == 1
    check manifest.dependencies[0].name == "zippy"
    check manifest.dependencies[0].rawConstraint == ">= 0.10.4"

  # ---------------------------------------------------------------------------
  # Pillar 4: Circular & Dangling Package Dependencies in Lockfiles
  # ---------------------------------------------------------------------------

  test "Direct circular dependency cycle detection (A -> B -> A)":
    var graph = initTable[string, seq[string]]()
    graph["pkgA"] = @["pkgB"]
    graph["pkgB"] = @["pkgA"]

    let cycles = detectCircularDependencies(graph)
    check cycles.len == 1
    check cycles[0] == @["pkgA", "pkgB", "pkgA"]

  test "Indirect circular dependency cycle detection (A -> B -> C -> A)":
    var graph = initTable[string, seq[string]]()
    graph["pkgA"] = @["pkgB"]
    graph["pkgB"] = @["pkgC"]
    graph["pkgC"] = @["pkgA"]
    graph["pkgD"] = @["pkgC"] # non-cyclic branch feeding into cycle

    let cycles = detectCircularDependencies(graph)
    check cycles.len == 1
    check cycles[0] == @["pkgA", "pkgB", "pkgC", "pkgA"]

  test "Self cycle detection (A -> A)":
    var graph = initTable[string, seq[string]]()
    graph["pkgA"] = @["pkgA"]

    let cycles = detectCircularDependencies(graph)
    check cycles.len == 1
    check cycles[0] == @["pkgA", "pkgA"]

  test "Acyclic DAG produces zero cycle detections":
    var graph = initTable[string, seq[string]]()
    graph["pkgA"] = @["pkgB", "pkgC"]
    graph["pkgB"] = @["pkgC"]
    graph["pkgC"] = @[]

    let cycles = detectCircularDependencies(graph)
    check cycles.len == 0
    check cycles == newSeq[seq[string]]()

  test "Dangling dependencies detection between manifest and lockfile":
    let manifestContent = [
      "version = \"1.0.0\"", "requires \"nim >= 2.0.0\"",
      "requires \"zippy >= 0.10.4\"", "requires \"yaml >= 2.1.0\"",
      "requires \"chronos >= 4.0.0\"",
    ].join("\n")

    let manifest = parseNimbleManifest(manifestContent)

    let lockJson = """{
  "version": 1,
  "packages": {
    "zippy": {
      "version": "0.10.4",
      "vcsRevision": "9a38f31234567890abcdef1234567890abcdef12",
      "url": "https://github.com/guzba/zippy",
      "downloadMethod": "git"
    }
  }
}"""
    let lock = parseLockFile(lockJson)

    let dangling = findDanglingDependencies(manifest, lock)
    # Both yaml and chronos are required in manifest but missing from lockfile
    check dangling.len == 2
    check dangling == @["yaml", "chronos"]

  test "Comprehensive lockfile integrity verification":
    let manifestContent =
      ["requires \"zippy >= 0.10.4\"", "requires \"yaml >= 2.1.0\""].join("\n")
    let manifest = parseNimbleManifest(manifestContent)

    # Lockfile with:
    # 1. Missing 'yaml' (dangling manifest dep)
    # 2. 'badPkg' with empty version and empty vcsRevision
    # 3. 'transPkg' requiring 'missingTransDep' (dangling transitive dep)
    # 4. Cycle between 'cycleA' and 'cycleB'
    let malformedLockJson = """{
  "version": 1,
  "packages": {
    "zippy": {
      "version": "0.10.4",
      "vcsRevision": "9a38f31234567890abcdef1234567890abcdef12",
      "url": "https://github.com/guzba/zippy",
      "downloadMethod": "git"
    },
    "badPkg": {
      "version": "",
      "vcsRevision": "",
      "url": "",
      "downloadMethod": "git"
    },
    "transPkg": {
      "version": "1.0.0",
      "vcsRevision": "abcdef1234567890abcdef1234567890abcdef12",
      "url": "https://github.com/axiomantic/transPkg",
      "downloadMethod": "git",
      "dependencies": ["missingTransDep"]
    },
    "cycleA": {
      "version": "1.0.0",
      "vcsRevision": "1111111111111111111111111111111111111111",
      "url": "https://github.com/axiomantic/cycleA",
      "downloadMethod": "git",
      "dependencies": ["cycleB"]
    },
    "cycleB": {
      "version": "1.0.0",
      "vcsRevision": "2222222222222222222222222222222222222222",
      "url": "https://github.com/axiomantic/cycleB",
      "downloadMethod": "git",
      "dependencies": ["cycleA"]
    }
  }
}"""
    let lock = parseLockFile(malformedLockJson)
    let issues = validateLockIntegrity(manifest, lock)

    check issues.len == 6
    check issues[0] ==
      "Dangling dependency: manifest requires 'yaml', but it is missing from lockfile"
    check issues[1] == "Malformed lockfile entry: package 'badPkg' has empty version"
    check issues[2] == "Malformed lockfile entry: package 'badPkg' has empty vcsRevision"
    check issues[3] == "Malformed lockfile entry: package 'badPkg' has empty url"
    check issues[4] ==
      "Dangling transitive dependency: package 'transPkg' requires 'missingTransDep', but it is missing from lockfile"
    check issues[5] == "Circular dependency detected: cycleA -> cycleB -> cycleA"

  # ---------------------------------------------------------------------------
  # Upstream Tag Parsing & Release Selection Adversarial Controls
  # ---------------------------------------------------------------------------
  test "Negative Control: parseGitLsRemoteTags immune to non-SemVer and malformed tags":
    let rawLsRemote = [
      "a1b2c3d4e5f67890123456789012345678901234\trefs/tags/v1.0.0",
      "1111111111111111111111111111111111111111\trefs/tags/v1.0.0^{}",
      "2222222222222222222222222222222222222222\trefs/tags/nightly",
      "3333333333333333333333333333333333333333\trefs/tags/devel",
      "4444444444444444444444444444444444444444\trefs/tags/release_candidate_1",
      "5555555555555555555555555555555555555555\trefs/tags/2.1.0",
    ].join("\n")

    # Must NOT raise ValueError on 'nightly' or 'devel'
    let tags = parseGitLsRemoteTags(rawLsRemote)
    check tags.len == 2
    check tags[0].name == "v1.0.0"
    check tags[0].semver == parseSemVersion("1.0.0")
    check tags[1].name == "2.1.0"
    check tags[1].semver == parseSemVersion("2.1.0")

  test "Negative Control: getLatestRelease prefers stable over prerelease by default":
    let tags = @[
      UpstreamTag(
        name: "v3.0.0-alpha.1",
        semver: parseSemVersion("3.0.0-alpha.1"),
        commitSha: "3333",
      ),
      UpstreamTag(name: "v2.5.0", semver: parseSemVersion("2.5.0"), commitSha: "2222"),
      UpstreamTag(name: "v2.4.0", semver: parseSemVersion("2.4.0"), commitSha: "1111"),
    ]
    let stableConstraint = parseVersionConstraint(">= 2.0.0")
    let latestStable = getLatestRelease(tags, stableConstraint)
    check latestStable.isSome
    check latestStable.get.semver == parseSemVersion("2.5.0")

    # If user explicitly tracks prerelease, allow prerelease
    let prereleaseConstraint = parseVersionConstraint(">= 3.0.0-alpha.0")
    let latestPrerelease = getLatestRelease(tags, prereleaseConstraint)
    check latestPrerelease.isSome
    check latestPrerelease.get.semver == parseSemVersion("3.0.0-alpha.1")

  test "Negative Control: findDanglingDependencies recognizes direct URL packages":
    let manifestText = """
requires "https://github.com/nim-lang/zip.git >= 0.3.0"
requires "yaml >= 1.0.0"
"""
    let manifest = parseNimbleManifest(manifestText)
    let lockJson = """{
  "version": 1,
  "packages": {
    "zip": {
      "version": "0.3.1",
      "vcsRevision": "abcdef1234567890abcdef1234567890abcdef12",
      "url": "https://github.com/nim-lang/zip.git",
      "downloadMethod": "git"
    },
    "yaml": {
      "version": "1.0.0",
      "vcsRevision": "1234567890abcdef1234567890abcdef12345678",
      "url": "https://github.com/flyx/nim-yaml",
      "downloadMethod": "git"
    }
  }
}"""
    let lock = parseLockFile(lockJson)
    let dangling = findDanglingDependencies(manifest, lock)
    # The URL package 'zip' must NOT be flagged as dangling!
    check dangling.len == 0
