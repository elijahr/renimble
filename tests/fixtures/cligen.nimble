# Package
version       = "1.6.0"
author        = "Charles Blake"
description   = "Infer & generate command-line interfaces / command-line parsers."
license       = "MIT/ISC"
srcDir        = "cligen"

# Dependencies
requires "nim >= 1.6.0"

task test, "Run test suite":
  exec "nim c -r test/test.nim"
