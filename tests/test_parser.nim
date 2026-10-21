import std/[unittest, options]
import ../src/dependanim/[types, declarative_parser]

suite "Nimble Declarative Parser":
  test "Extract package metadata":
    let nimbleText = """
# Package Metadata
version       = "0.2.1"
author        = "Axiomantic Team"
description   = "High performance tool"
license       = "MIT"

# Dependencies
requires "nim >= 2.0.0"
requires "zippy >= 0.10.4"
"""
    let manifest = parseNimbleManifest(nimbleText)
    check manifest.version == "0.2.1"
    check manifest.author == "Axiomantic Team"
    check manifest.license == "MIT"
    check manifest.dependencies.len == 2
    check manifest.dependencies[0].name == "nim"
    check manifest.dependencies[1].name == "zippy"

  test "Parse multiple requires and feature flags":
    let nimbleText = """
requires "nim >= 2.0.0", "yaml >= 2.1.0"
requires "chronos#master"
requires "norm[sqlite] >= 2.2.0" # Database ORM
"""
    let manifest = parseNimbleManifest(nimbleText)
    check manifest.dependencies.len == 4
    check manifest.dependencies[0].name == "nim"
    check manifest.dependencies[1].name == "yaml"
    check manifest.dependencies[2].name == "chronos"
    check manifest.dependencies[3].name == "norm"
    check manifest.dependencies[3].feature.isSome
    check manifest.dependencies[3].feature.get == "sqlite"
