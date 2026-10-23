import std/options
import types, version

type
  BoundKind* = enum
    bkNegativeInfinity,
    bkValue,
    bkPositiveInfinity

  SemVerBound* = object
    kind*: BoundKind
    ver*: SemVersion
    inclusive*: bool

  VersionInterval* = object
    low*: SemVerBound
    high*: SemVerBound

  IntervalNode*[T] = ref object
    interval*: VersionInterval
    maxHigh*: SemVerBound
    data*: T
    left*, right*: IntervalNode[T]

  VersionIntervalTree*[T] = object
    root*: IntervalNode[T]
    count*: int

  VersionIntervalSet* = object
    intervals*: seq[VersionInterval]

proc bound*(v: SemVersion, inclusive: bool = true): SemVerBound {.inline.} =
  SemVerBound(kind: bkValue, ver: v, inclusive: inclusive)

proc negInf*(): SemVerBound {.inline.} =
  SemVerBound(kind: bkNegativeInfinity, inclusive: false)

proc posInf*(): SemVerBound {.inline.} =
  SemVerBound(kind: bkPositiveInfinity, inclusive: false)

proc cmpBound*(a, b: SemVerBound): int =
  if a.kind == b.kind:
    if a.kind == bkValue:
      let c = cmp(a.ver, b.ver)
      if c != 0: return c
      if a.inclusive == b.inclusive: return 0
      return if a.inclusive: 1 else: -1
    return 0
  if a.kind == bkNegativeInfinity: return -1
  if b.kind == bkNegativeInfinity: return 1
  if a.kind == bkPositiveInfinity: return 1
  return -1

proc `<`*(a, b: SemVerBound): bool {.inline.} = cmpBound(a, b) < 0
proc `<=`*(a, b: SemVerBound): bool {.inline.} = cmpBound(a, b) <= 0
proc `==`*(a, b: SemVerBound): bool {.inline.} = cmpBound(a, b) == 0

proc maxBound*(a, b: SemVerBound): SemVerBound {.inline.} =
  if a < b: b else: a

proc newInterval*(low, high: SemVerBound): VersionInterval {.inline.} =
  VersionInterval(low: low, high: high)

proc contains*(iv: VersionInterval, v: SemVersion): bool =
  # Test low bound
  case iv.low.kind
  of bkNegativeInfinity:
    discard
  of bkValue:
    if iv.low.inclusive:
      if v < iv.low.ver: return false
    else:
      if v <= iv.low.ver: return false
  of bkPositiveInfinity:
    return false

  # Test high bound
  case iv.high.kind
  of bkPositiveInfinity:
    discard
  of bkValue:
    if iv.high.inclusive:
      if v > iv.high.ver: return false
    else:
      if v >= iv.high.ver: return false
  of bkNegativeInfinity:
    return false

  return true

proc intersects*(a, b: VersionInterval): bool =
  # a and b intersect if a.low <= b.high and b.low <= a.high
  if a.low.kind == bkPositiveInfinity or b.low.kind == bkPositiveInfinity:
    return false
  if a.high.kind == bkNegativeInfinity or b.high.kind == bkNegativeInfinity:
    return false

  # Check if a is strictly above b
  if a.low.kind == bkValue and b.high.kind == bkValue:
    if a.low.ver > b.high.ver: return false
    if a.low.ver == b.high.ver and (not a.low.inclusive or not b.high.inclusive):
      return false

  # Check if b is strictly above a
  if b.low.kind == bkValue and a.high.kind == bkValue:
    if b.low.ver > a.high.ver: return false
    if b.low.ver == a.high.ver and (not b.low.inclusive or not a.high.inclusive):
      return false

  return true

proc singleConstraintToInterval*(c: SingleConstraint): VersionInterval =
  if c.spec.kind != vkSemVer:
    return newInterval(negInf(), posInf())

  let target = c.spec.semver
  case c.op
  of voNone, voEq:
    result = newInterval(bound(target, true), bound(target, true))
  of voGt:
    result = newInterval(bound(target, false), posInf())
  of voGe:
    result = newInterval(bound(target, true), posInf())
  of voLt:
    result = newInterval(negInf(), bound(target, false))
  of voLe:
    result = newInterval(negInf(), bound(target, true))
  of voCaret:
    # ^= Caret: e.g. ^= 1.2.3 -> [1.2.3, 2.0.0)
    let low = bound(target, true)
    var highVer = target
    if target.major > 0:
      highVer.major += 1
      highVer.minor = 0
      highVer.patch = 0
    elif target.minor > 0:
      highVer.minor += 1
      highVer.patch = 0
    else:
      highVer.patch += 1
    result = newInterval(low, bound(highVer, false))
  of voTilde:
    # ~= Tilde: e.g. ~= 1.2.3 -> [1.2.3, 1.3.0)
    let low = bound(target, true)
    var highVer = target
    highVer.minor += 1
    highVer.patch = 0
    result = newInterval(low, bound(highVer, false))

proc updateMaxHigh[T](node: IntervalNode[T]) =
  if node == nil: return
  node.maxHigh = node.interval.high
  if node.left != nil:
    node.maxHigh = maxBound(node.maxHigh, node.left.maxHigh)
  if node.right != nil:
    node.maxHigh = maxBound(node.maxHigh, node.right.maxHigh)

proc insertNode[T](root: IntervalNode[T], iv: VersionInterval, data: T): IntervalNode[T] =
  if root == nil:
    return IntervalNode[T](
      interval: iv,
      maxHigh: iv.high,
      data: data,
      left: nil,
      right: nil
    )

  if iv.low < root.interval.low:
    root.left = insertNode(root.left, iv, data)
  else:
    root.right = insertNode(root.right, iv, data)

  updateMaxHigh(root)
  return root

proc insert*[T](tree: var VersionIntervalTree[T], interval: VersionInterval, data: T) =
  tree.root = insertNode(tree.root, interval, data)
  inc tree.count

proc queryPoint*[T](tree: VersionIntervalTree[T], point: SemVersion): seq[T] =
  result = @[]

  proc search(node: IntervalNode[T], res: var seq[T]) =
    if node == nil: return
    # If point is strictly greater than subtree maxHigh, no overlap possible
    if node.maxHigh.kind == bkValue and node.maxHigh.ver < point:
      return

    if node.left != nil:
      search(node.left, res)

    if contains(node.interval, point):
      res.add(node.data)

    if node.right != nil:
      search(node.right, res)

  search(tree.root, result)

proc queryOverlaps*[T](tree: VersionIntervalTree[T], query: VersionInterval): seq[T] =
  result = @[]

  proc search(node: IntervalNode[T], res: var seq[T]) =
    if node == nil: return

    # Prune if query.low is strictly greater than subtree maxHigh
    if node.maxHigh.kind == bkValue and query.low.kind == bkValue:
      if query.low.ver > node.maxHigh.ver:
        return

    if node.left != nil:
      search(node.left, res)

    if intersects(node.interval, query):
      res.add(node.data)

    if node.right != nil:
      search(node.right, res)

  search(tree.root, result)

proc newVersionIntervalTree*[T](): VersionIntervalTree[T] =
  VersionIntervalTree[T](root: nil, count: 0)
