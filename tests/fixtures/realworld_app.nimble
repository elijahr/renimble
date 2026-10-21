# Package
version       = "0.5.0"
author        = "Nim Developer"
description   = "Full real-world application manifest"
license       = "MIT"
srcDir        = "src"
bin           = @["myapp"]

# Dependencies
requires "nim >= 2.0.0"
requires "zippy >= 0.10.0" # Fast compression
requires 'yaml >= 1.0.0'
requires "cligen >= 1.6.0", "ws >= 0.5.0"

task test, "Run test suite":
  exec "nim c -r tests/test_all.nim"
