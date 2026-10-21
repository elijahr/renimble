# Package
version       = "0.4.2"
author        = "Nim Community"
description   = "Multi-line requires package test"
license       = "MIT"
srcDir        = "src"

# Multi-line comma-separated requires
requires "nim >= 1.6.0",
         "zippy >= 0.10.4",
         "yaml >= 1.0.0"

# Subsequent requires
requires "cligen >= 1.5.0"
