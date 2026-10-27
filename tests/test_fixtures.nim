import unittest, std/[os, strutils, options]
import ../src/renimble/[types, declarative_parser, rewriter]

suite "Real-World Fixtures & Manifest Parsing":
  let fixturesDir = currentSourcePath().parentDir / "fixtures"

  test "Parse zippy.nimble fixture":
    let content = readFile(fixturesDir / "zippy.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "zippy.nimble")
    check m.version == "0.10.16"
    check m.author == "Ryan Oldenburg"
    check m.license == "MIT"
    check m.dependencies.len == 1
    check m.dependencies[0].name == "nim"
    check m.dependencies[0].rawConstraint == ">= 1.0.0"

  test "Parse yaml.nimble fixture":
    let content = readFile(fixturesDir / "yaml.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "yaml.nimble")
    check m.version == "1.1.0"
    check m.author == "Felix Krause"
    check m.dependencies.len == 1
    check m.dependencies[0].name == "nim"
    check m.dependencies[0].rawConstraint == ">= 1.6.0"

  test "Parse cligen.nimble fixture with task blocks":
    let content = readFile(fixturesDir / "cligen.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "cligen.nimble")
    check m.version == "1.6.0"
    check m.author == "Charles Blake"
    check m.license == "MIT/ISC"
    check m.dependencies.len == 1
    check m.dependencies[0].name == "nim"

  test "Parse multi-line comma-separated requires fixture":
    let content = readFile(fixturesDir / "multiline_requires.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "multiline_requires.nimble")
    check m.version == "0.4.2"
    check m.dependencies.len == 4
    check m.dependencies[0].name == "nim"
    check m.dependencies[1].name == "zippy"
    check m.dependencies[1].rawConstraint == ">= 0.10.4"
    check m.dependencies[2].name == "yaml"
    check m.dependencies[2].rawConstraint == ">= 1.0.0"
    check m.dependencies[3].name == "cligen"
    check m.dependencies[3].rawConstraint == ">= 1.5.0"

  test "Parse VCS #head, branch, and commit pins":
    let content = readFile(fixturesDir / "head_pins.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "head_pins.nimble")
    check m.version == "1.2.0"
    check m.dependencies.len == 4

    # chronos#head
    check m.dependencies[1].name == "chronos"
    check m.dependencies[1].constraint.constraints.len == 1
    check m.dependencies[1].constraint.constraints[0].spec.kind == vkHead
    check m.dependencies[1].constraint.constraints[0].spec.vcsRef == "head"

    # https://github.com/status-im/nim-eth#master
    check m.dependencies[2].name == "https://github.com/status-im/nim-eth"
    check m.dependencies[2].constraint.constraints.len == 1
    check m.dependencies[2].constraint.constraints[0].spec.kind == vkBranch
    check m.dependencies[2].constraint.constraints[0].spec.vcsRef == "master"

    # bearlibterminal#1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b
    check m.dependencies[3].name == "bearlibterminal"
    check m.dependencies[3].constraint.constraints.len == 1
    check m.dependencies[3].constraint.constraints[0].spec.kind == vkCommit
    check m.dependencies[3].constraint.constraints[0].spec.vcsRef ==
      "1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b"

  test "Parse feature flags and varied constraint operators":
    let content = readFile(fixturesDir / "feature_flags.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "feature_flags.nimble")
    check m.version == "3.0.1"
    check m.dependencies.len == 4

    # pkg[ssl] >= 1.2.0
    check m.dependencies[1].name == "pkg"
    check m.dependencies[1].feature == some("ssl")
    check m.dependencies[1].constraint.constraints[0].op == voGe

    # chronos[posix] ^= 3.0.0
    check m.dependencies[2].name == "chronos"
    check m.dependencies[2].feature == some("posix")
    check m.dependencies[2].constraint.constraints[0].op == voCaret

    # yaml[emitter] ~= 1.1.0
    check m.dependencies[3].name == "yaml"
    check m.dependencies[3].feature == some("emitter")
    check m.dependencies[3].constraint.constraints[0].op == voTilde

  test "Parse full real-world application manifest":
    let content = readFile(fixturesDir / "realworld_app.nimble")
    let m = parseNimbleManifest(content, fixturesDir / "realworld_app.nimble")
    check m.version == "0.5.0"
    check m.dependencies.len == 5
    check m.dependencies[0].name == "nim"
    check m.dependencies[1].name == "zippy"
    check m.dependencies[2].name == "yaml"
    check m.dependencies[3].name == "cligen"
    check m.dependencies[4].name == "ws"

suite "In-Place Rewriting on Real-World Fixtures":
  let fixturesDir = currentSourcePath().parentDir / "fixtures"

  test "Rewrite multi-line continuation dependency":
    let content = readFile(fixturesDir / "multiline_requires.nimble")
    let updated = rewriteNimbleFile(content, "zippy", ">= 0.11.0")
    check "zippy >= 0.11.0" in updated
    check "yaml >= 1.0.0" in updated
    check "cligen >= 1.5.0" in updated

    # Verify re-parsing the updated manifest
    let m = parseNimbleManifest(updated)
    check m.dependencies[1].name == "zippy"
    check m.dependencies[1].rawConstraint == ">= 0.11.0"

  test "Rewrite feature-flagged dependency while preserving brackets":
    let content = readFile(fixturesDir / "feature_flags.nimble")
    let updated = rewriteNimbleFile(content, "chronos", "^= 3.1.0")
    check "chronos[posix] ^= 3.1.0" in updated
    check "pkg[ssl] >= 1.2.0" in updated
    check "yaml[emitter] ~= 1.1.0" in updated

  test "Preserve single quotes and comments in realworld app":
    let content = readFile(fixturesDir / "realworld_app.nimble")
    let updated = rewriteNimbleFile(content, "yaml", ">= 1.2.0")
    check "'yaml >= 1.2.0'" in updated
    check "# Fast compression" in updated
    check "task test, \"Run test suite\":" in updated
