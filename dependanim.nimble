# Package

version       = "0.1.0"
author        = "Axiomantic"
description   = "Definitive automated dependency updater for Nim projects (.nimble & nimble.lock)"
license       = "MIT"
srcDir        = "src"
bin           = @["dependanim"]

# Dependencies

requires "nim >= 2.0.0"
requires "yaml >= 2.1.0"

# Tasks

task test, "Run the full test suite":
  exec "nim c -r tests/test_all.nim"

task buildRelease, "Build optimized release binary":
  exec "nim c -d:release --opt:speed -o:bin/dependanim src/dependanim.nim"
