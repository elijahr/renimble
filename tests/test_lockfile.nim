import std/[unittest, tables, strutils]
import ../src/dependanim/[types, lockfile]

suite "Nimble Lockfile Sync":
  test "Parse and update lockfile":
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
}
"""
    var lock = parseLockFile(lockJson)
    check lock.version == 1
    check lock.packages.hasKey("zippy")
    check lock.packages["zippy"].version == "0.10.4"

    updateLockPackage(lock, "zippy", "0.11.0", "fedcba0987654321fedcba0987654321fedcba09")
    check lock.packages["zippy"].version == "0.11.0"
    check lock.packages["zippy"].vcsRevision == "fedcba0987654321fedcba0987654321fedcba09"

    let serialized = serializeLockFile(lock)
    check "\"0.11.0\"" in serialized
    check "\"fedcba0987654321fedcba0987654321fedcba09\"" in serialized
