import std/unittest
import ../src/dependanim/[types, version]

suite "Nimble Version & Constraint Engine":
  test "SemVer parsing standard versions":
    let v1 = parseSemVersion("1.2.3")
    check v1.major == 1
    check v1.minor == 2
    check v1.patch == 3
    check v1.prerelease == ""
    check v1.build == ""

    let v2 = parseSemVersion("v2.0.0-rc.1+sha.abcdef")
    check v2.major == 2
    check v2.minor == 0
    check v2.patch == 0
    check v2.prerelease == "rc.1"
    check v2.build == "sha.abcdef"

  test "SemVer comparison precedence":
    let v100 = parseSemVersion("1.0.0")
    let v200 = parseSemVersion("2.0.0")
    let v110 = parseSemVersion("1.1.0")
    let v101 = parseSemVersion("1.0.1")
    let v100rc = parseSemVersion("1.0.0-rc.1")

    check v100 < v200
    check v100 < v110
    check v100 < v101
    check v100rc < v100
    check v100 == parseSemVersion("1.0.0")

  test "Single constraint evaluation":
    let v = parseSemVersion("1.2.3")
    check satisfiesSingle(v, parseSingleConstraint(">= 1.0.0"))
    check satisfiesSingle(v, parseSingleConstraint("< 2.0.0"))
    check satisfiesSingle(v, parseSingleConstraint("<= 1.2.3"))
    check satisfiesSingle(v, parseSingleConstraint("== 1.2.3"))
    check not satisfiesSingle(v, parseSingleConstraint("== 1.2.4"))
    check not satisfiesSingle(v, parseSingleConstraint("> 1.2.3"))

  test "Caret (^=) and Tilde (~=) operators":
    let targetCaret = parseSemVersion("1.2.3")
    check satisfiesSingle(parseSemVersion("1.2.4"), parseSingleConstraint("^= 1.2.3"))
    check satisfiesSingle(parseSemVersion("1.5.0"), parseSingleConstraint("^= 1.2.3"))
    check not satisfiesSingle(parseSemVersion("2.0.0"), parseSingleConstraint("^= 1.2.3"))
    check not satisfiesSingle(parseSemVersion("1.2.2"), parseSingleConstraint("^= 1.2.3"))

    # Tilde: patch-level bumps only
    check satisfiesSingle(parseSemVersion("1.2.4"), parseSingleConstraint("~= 1.2.3"))
    check not satisfiesSingle(parseSemVersion("1.3.0"), parseSingleConstraint("~= 1.2.3"))

  test "Intersected constraints with '&'":
    let c = parseVersionConstraint(">= 1.0.0 & <= 1.5.0")
    check satisfies(parseSemVersion("1.0.0"), c)
    check satisfies(parseSemVersion("1.2.5"), c)
    check satisfies(parseSemVersion("1.5.0"), c)
    check not satisfies(parseSemVersion("0.9.9"), c)
    check not satisfies(parseSemVersion("1.5.1"), c)

  test "Constraint string updating":
    let updated1 = updateConstraintString(">= 1.0.0", parseSemVersion("1.2.0"))
    check updated1 == ">= 1.2.0"

    let updated2 = updateConstraintString("^= 0.4.1", parseSemVersion("0.5.0"))
    check updated2 == "^= 0.5.0"

    let updated3 = updateConstraintString(">= 1.0.0 & <= 1.5.0", parseSemVersion("1.6.0"))
    check updated3 == ">= 1.6.0 & <= 1.6.0"
