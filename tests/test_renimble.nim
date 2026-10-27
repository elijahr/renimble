import unittest
import renimble

suite "renimble":
  test "hello returns expected greeting":
    check hello() == "hello from renimble"

  test "version present":
    check projectVersion == "0.0.1"
