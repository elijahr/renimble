import std/unittest
import ../src/dependanim/[version, interval_tree]

suite "SemVer Interval Tree & Range Algebra":
  test "Convert SingleConstraint to VersionInterval":
    let caret = singleConstraintToInterval(parseSingleConstraint("^= 1.2.3"))
    check caret.low.ver == parseSemVersion("1.2.3")
    check caret.low.inclusive == true
    check caret.high.ver == parseSemVersion("2.0.0")
    check caret.high.inclusive == false

    let tilde = singleConstraintToInterval(parseSingleConstraint("~= 1.2.3"))
    check tilde.low.ver == parseSemVersion("1.2.3")
    check tilde.high.ver == parseSemVersion("1.3.0")
    check tilde.high.inclusive == false

    let ge = singleConstraintToInterval(parseSingleConstraint(">= 2.0.0"))
    check ge.low.ver == parseSemVersion("2.0.0")
    check ge.low.inclusive == true
    check ge.high.kind == bkPositiveInfinity

  test "Interval point containment":
    let iv = newInterval(bound(parseSemVersion("1.0.0"), true), bound(parseSemVersion("2.0.0"), false))
    check contains(iv, parseSemVersion("1.0.0"))
    check contains(iv, parseSemVersion("1.5.0"))
    check contains(iv, parseSemVersion("1.9.9"))
    check not contains(iv, parseSemVersion("0.9.9"))
    check not contains(iv, parseSemVersion("2.0.0"))

  test "Interval intersection":
    let a = newInterval(bound(parseSemVersion("1.0.0"), true), bound(parseSemVersion("2.0.0"), true))
    let b = newInterval(bound(parseSemVersion("1.5.0"), true), bound(parseSemVersion("2.5.0"), true))
    let c = newInterval(bound(parseSemVersion("2.1.0"), true), bound(parseSemVersion("3.0.0"), true))

    check intersects(a, b)
    check intersects(b, c)
    check not intersects(a, c)

  test "Interval tree insertion and point-stabbing queries":
    var tree = newVersionIntervalTree[string]()

    tree.insert(newInterval(bound(parseSemVersion("1.0.0"), true), bound(parseSemVersion("2.0.0"), false)), "pkgA")
    tree.insert(newInterval(bound(parseSemVersion("1.5.0"), true), bound(parseSemVersion("2.5.0"), true)), "pkgB")
    tree.insert(newInterval(bound(parseSemVersion("0.5.0"), true), bound(parseSemVersion("0.9.0"), true)), "pkgC")
    tree.insert(newInterval(bound(parseSemVersion("3.0.0"), true), posInf()), "pkgD")

    check tree.count == 4

    let q1 = tree.queryPoint(parseSemVersion("1.2.0"))
    check q1 == @["pkgA"]

    let q2 = tree.queryPoint(parseSemVersion("1.8.0"))
    check "pkgA" in q2
    check "pkgB" in q2
    check q2.len == 2

    let q3 = tree.queryPoint(parseSemVersion("0.7.0"))
    check q3 == @["pkgC"]

    let q4 = tree.queryPoint(parseSemVersion("4.0.0"))
    check q4 == @["pkgD"]

    let qNone = tree.queryPoint(parseSemVersion("2.8.0"))
    check qNone.len == 0

  test "Interval tree range overlap queries":
    var tree = newVersionIntervalTree[string]()
    tree.insert(newInterval(bound(parseSemVersion("1.0.0"), true), bound(parseSemVersion("1.5.0"), true)), "v1")
    tree.insert(newInterval(bound(parseSemVersion("1.6.0"), true), bound(parseSemVersion("2.0.0"), true)), "v2")
    tree.insert(newInterval(bound(parseSemVersion("2.5.0"), true), bound(parseSemVersion("3.0.0"), true)), "v3")

    let queryRange = newInterval(bound(parseSemVersion("1.4.0"), true), bound(parseSemVersion("1.7.0"), true))
    let overlaps = tree.queryOverlaps(queryRange)

    check "v1" in overlaps
    check "v2" in overlaps
    check "v3" notin overlaps
    check overlaps.len == 2
