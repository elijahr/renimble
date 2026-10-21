import std/[unittest, strutils]
import ../src/dependanim/rewriter

suite "In-Place Nimble Rewriter":
  test "Preserve comments and indentation":
    let original = """
# Package
version       = "0.1.0"
author        = "Axiomantic"

# Dependencies
requires "nim >= 2.0.0"
requires "zippy >= 0.10.4" # Fast deflate compression
requires "yaml >= 2.1.0"

# Tasks
task test, "Run tests":
  exec "nim c -r tests/test_all.nim"
"""
    let updated = rewriteNimbleFile(original, "zippy", ">= 0.11.0")

    check "requires \"zippy >= 0.11.0\" # Fast deflate compression" in updated
    check "task test, \"Run tests\":" in updated
    check "requires \"yaml >= 2.1.0\"" in updated
    check "requires \"nim >= 2.0.0\"" in updated

  test "Preserve single quotes and feature flags":
    let original = """
requires 'norm[sqlite] >= 2.2.0'
"""
    let updated = rewriteNimbleFile(original, "norm", ">= 2.3.0")
    check updated.strip() == "requires 'norm[sqlite] >= 2.3.0'"
