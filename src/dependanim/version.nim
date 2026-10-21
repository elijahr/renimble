import std/[strutils, parseutils]
import types

proc parseSemVersion*(s: string): SemVersion =
  var clean = s.strip()
  if clean.startsWith("v") or clean.startsWith("V"):
    clean = clean[1..^1]

  # Split build metadata (+)
  var buildMeta = ""
  let plusIdx = clean.find('+')
  if plusIdx != -1:
    buildMeta = clean[(plusIdx + 1)..^1]
    clean = clean[0..<plusIdx]

  # Split prerelease (-)
  var preRelease = ""
  let dashIdx = clean.find('-')
  if dashIdx != -1:
    preRelease = clean[(dashIdx + 1)..^1]
    clean = clean[0..<dashIdx]

  let parts = clean.split('.')
  var maj, min, pat = 0
  if parts.len >= 1 and parts[0].len > 0:
    discard parseInt(parts[0], maj)
  if parts.len >= 2 and parts[1].len > 0:
    discard parseInt(parts[1], min)
  if parts.len >= 3 and parts[2].len > 0:
    discard parseInt(parts[2], pat)

  result = SemVersion(
    major: maj,
    minor: min,
    patch: pat,
    prerelease: preRelease,
    build: buildMeta
  )

proc `$`*(v: SemVersion): string =
  result = $v.major & "." & $v.minor & "." & $v.patch
  if v.prerelease.len > 0:
    result.add("-" & v.prerelease)
  if v.build.len > 0:
    result.add("+" & v.build)

proc cmp*(a, b: SemVersion): int =
  if a.major != b.major:
    return system.cmp(a.major, b.major)
  if a.minor != b.minor:
    return system.cmp(a.minor, b.minor)
  if a.patch != b.patch:
    return system.cmp(a.patch, b.patch)

  # SemVer 2.0: A version without prerelease has higher precedence than with prerelease
  if a.prerelease.len == 0 and b.prerelease.len > 0:
    return 1
  if a.prerelease.len > 0 and b.prerelease.len == 0:
    return -1
  if a.prerelease.len > 0 and b.prerelease.len > 0:
    return system.cmp(a.prerelease, b.prerelease)

  return 0

proc `<`*(a, b: SemVersion): bool {.inline.} = cmp(a, b) < 0
proc `<=`*(a, b: SemVersion): bool {.inline.} = cmp(a, b) <= 0
proc `==`*(a, b: SemVersion): bool {.inline.} = cmp(a, b) == 0

proc parseSingleConstraint*(token: string): SingleConstraint =
  var clean = token.strip()
  var op = voNone

  if clean.startsWith(">="):
    op = voGe
    clean = clean[2..^1].strip()
  elif clean.startsWith("<="):
    op = voLe
    clean = clean[2..^1].strip()
  elif clean.startsWith("=="):
    op = voEq
    clean = clean[2..^1].strip()
  elif clean.startsWith("^="):
    op = voCaret
    clean = clean[2..^1].strip()
  elif clean.startsWith("~="):
    op = voTilde
    clean = clean[2..^1].strip()
  elif clean.startsWith(">"):
    op = voGt
    clean = clean[1..^1].strip()
  elif clean.startsWith("<"):
    op = voLt
    clean = clean[1..^1].strip()
  elif clean.startsWith("="):
    op = voEq
    clean = clean[1..^1].strip()

  var spec: VersionSpec
  if clean.startsWith("#head") or clean == "#head":
    spec = VersionSpec(kind: vkHead, vcsRef: "head")
  elif clean.startsWith("#"):
    let refName = clean[1..^1]
    if refName.len == 40 and refName.allCharsInSet(HexDigits):
      spec = VersionSpec(kind: vkCommit, vcsRef: refName)
    else:
      spec = VersionSpec(kind: vkBranch, vcsRef: refName)
  else:
    spec = VersionSpec(kind: vkSemVer, semver: parseSemVersion(clean), vcsRef: clean)

  result = SingleConstraint(op: op, spec: spec)

proc parseVersionConstraint*(raw: string): VersionConstraint =
  let clean = raw.strip()
  if clean.len == 0 or clean == "*":
    return VersionConstraint(isAny: true, constraints: @[])

  var constraints: seq[SingleConstraint] = @[]
  # Nimble constraints can be separated by '&'
  for part in clean.split('&'):
    let p = part.strip()
    if p.len > 0:
      constraints.add(parseSingleConstraint(p))

  result = VersionConstraint(
    isAny: constraints.len == 0,
    constraints: constraints
  )

proc satisfiesSingle*(v: SemVersion, c: SingleConstraint): bool =
  if c.spec.kind != vkSemVer:
    return true # Non-semver VCS pins handle separately

  let target = c.spec.semver
  case c.op
  of voNone, voEq:
    return v == target
  of voLt:
    return v < target
  of voLe:
    return v <= target
  of voGt:
    return v > target
  of voGe:
    return v >= target
  of voCaret:
    # ^= Caret: Allows changes that do not modify left-most non-zero digit
    if target.major > 0:
      return v >= target and v.major == target.major
    elif target.minor > 0:
      return v >= target and v.major == 0 and v.minor == target.minor
    else:
      return v == target
  of voTilde:
    # ~= Tilde: Allows patch level changes if minor specified
    return v >= target and v.major == target.major and v.minor == target.minor

proc satisfies*(v: SemVersion, vc: VersionConstraint): bool =
  if vc.isAny or vc.constraints.len == 0:
    return true
  for c in vc.constraints:
    if not satisfiesSingle(v, c):
      return false
  return true

proc getBumpType*(current, target: SemVersion): BumpType =
  if target.major > current.major:
    return btMajor
  elif target.minor > current.minor:
    return btMinor
  elif target.patch > current.patch:
    return btPatch
  return btNone

proc updateConstraintString*(rawConstraint: string, targetVersion: SemVersion): string =
  ## Given a constraint string like ">= 1.0.0 & <= 1.5.0" or "^= 0.4.1" or "0.2.0",
  ## updates the constraint bound to reference the new target version while preserving
  ## the operator style.
  let parsed = parseVersionConstraint(rawConstraint)
  if parsed.isAny:
    return ""

  var parts: seq[string] = @[]
  for c in parsed.constraints:
    let opStr = case c.op
      of voNone: ""
      of voEq: "== "
      of voLt: "< "
      of voLe: "<= "
      of voGt: "> "
      of voGe: ">= "
      of voCaret: "^= "
      of voTilde: "~= "

    if c.op in {voGe, voGt, voCaret, voTilde, voEq, voNone}:
      parts.add(opStr & $targetVersion)
    else:
      # Keep upper bounds or adapt them if target exceeds
      if c.spec.kind == vkSemVer and targetVersion >= c.spec.semver:
        # If bumping past an upper bound, widen upper bound to next major or patch
        parts.add(opStr & $targetVersion)
      else:
        parts.add(opStr & (if c.spec.kind == vkSemVer: $c.spec.semver else: c.spec.vcsRef))

  result = parts.join(" & ")
