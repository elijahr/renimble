import std/strutils
import types

proc parseSemVersion*(s: string): SemVersion =
  var clean = s.strip()
  if clean.len == 0:
    raise newException(ValueError, "Empty version string")

  if clean.startsWith("v") or clean.startsWith("V"):
    clean = clean[1 ..^ 1]

  if clean.len == 0:
    raise newException(ValueError, "Invalid SemVer: version missing after 'v' prefix")

  # Split build metadata (+)
  var buildMeta = ""
  let plusIdx = clean.find('+')
  if plusIdx != -1:
    buildMeta = clean[(plusIdx + 1) ..^ 1]
    clean = clean[0 ..< plusIdx]

  # Split prerelease (-)
  var preRelease = ""
  let dashIdx = clean.find('-')
  if dashIdx != -1:
    preRelease = clean[(dashIdx + 1) ..^ 1]
    clean = clean[0 ..< dashIdx]

  let parts = clean.split('.')
  if parts.len < 1 or parts.len > 3:
    raise newException(
      ValueError,
      "Invalid SemVer format (must have 1-3 dot-separated numeric parts): " & s,
    )

  var maj, min, pat = 0
  if parts.len >= 1:
    if parts[0].len == 0 or not parts[0].allCharsInSet(Digits):
      raise newException(
        ValueError, "Invalid major version segment in '" & s & "': " & parts[0]
      )
    maj = strutils.parseInt(parts[0])

  if parts.len >= 2:
    if parts[1].len == 0 or not parts[1].allCharsInSet(Digits):
      raise newException(
        ValueError, "Invalid minor version segment in '" & s & "': " & parts[1]
      )
    min = strutils.parseInt(parts[1])

  if parts.len >= 3:
    if parts[2].len == 0 or not parts[2].allCharsInSet(Digits):
      raise newException(
        ValueError, "Invalid patch version segment in '" & s & "': " & parts[2]
      )
    pat = strutils.parseInt(parts[2])

  result = SemVersion(
    major: maj, minor: min, patch: pat, prerelease: preRelease, build: buildMeta
  )

proc `$`*(v: SemVersion): string =
  result = $v.major & "." & $v.minor & "." & $v.patch
  if v.prerelease.len > 0:
    result.add("-" & v.prerelease)
  if v.build.len > 0:
    result.add("+" & v.build)

proc cmpPrerelease*(a, b: string): int =
  ## Compares two SemVer 2.0 prerelease strings complying with section 11.4:
  ## Identifiers consisting of only digits are compared numerically,
  ## identifiers with letters/hyphens are compared lexically.
  if a == b:
    return 0
  let aParts = a.split('.')
  let bParts = b.split('.')
  let minLen = min(aParts.len, bParts.len)

  for i in 0 ..< minLen:
    let ap = aParts[i]
    let bp = bParts[i]
    if ap != bp:
      let aIsNum = ap.len > 0 and ap.allCharsInSet(Digits)
      let bIsNum = bp.len > 0 and bp.allCharsInSet(Digits)
      if aIsNum and bIsNum:
        let aVal = strutils.parseInt(ap)
        let bVal = strutils.parseInt(bp)
        if aVal != bVal:
          return system.cmp(aVal, bVal)
      elif aIsNum and not bIsNum:
        return -1
      elif not aIsNum and bIsNum:
        return 1
      else:
        let c = system.cmp(ap, bp)
        if c != 0:
          return c

  return system.cmp(aParts.len, bParts.len)

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
    return cmpPrerelease(a.prerelease, b.prerelease)

  return 0

proc `<`*(a, b: SemVersion): bool {.inline.} =
  cmp(a, b) < 0

proc `<=`*(a, b: SemVersion): bool {.inline.} =
  cmp(a, b) <= 0

proc `==`*(a, b: SemVersion): bool {.inline.} =
  cmp(a, b) == 0

proc parseSingleConstraint*(token: string): SingleConstraint =
  var clean = token.strip()
  if clean.len == 0:
    raise newException(ValueError, "Empty constraint token")

  var op = voNone
  var opFound = false

  if clean.startsWith(">="):
    op = voGe
    clean = clean[2 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("<="):
    op = voLe
    clean = clean[2 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("=="):
    op = voEq
    clean = clean[2 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("!="):
    op = voNe
    clean = clean[2 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("^="):
    op = voCaret
    clean = clean[2 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("~="):
    op = voTilde
    clean = clean[2 ..^ 1].strip()
    opFound = true
  elif clean.startsWith(">"):
    op = voGt
    clean = clean[1 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("<"):
    op = voLt
    clean = clean[1 ..^ 1].strip()
    opFound = true
  elif clean.startsWith("="):
    op = voEq
    clean = clean[1 ..^ 1].strip()
    opFound = true

  # Reject invalid operator symbols or consecutive operator punctuation
  if clean.len > 0 and clean[0] in {'!', '=', '<', '>', '^', '~', '?', '@', '$', '%'}:
    raise newException(
      ValueError, "Invalid or consecutive constraint operator in: " & token
    )

  if clean.len == 0:
    raise newException(ValueError, "Constraint missing version operand: " & token)

  var spec: VersionSpec
  if clean.startsWith("#head") or clean == "#head":
    spec = VersionSpec(kind: vkHead, vcsRef: "head")
  elif clean.startsWith("#"):
    let refName = clean[1 ..^ 1]
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

  result = VersionConstraint(isAny: constraints.len == 0, constraints: constraints)

proc satisfiesSingle*(v: SemVersion, c: SingleConstraint): bool =
  if c.spec.kind != vkSemVer:
    return true # Non-semver VCS pins handle separately

  let target = c.spec.semver
  case c.op
  of voNone, voEq:
    return v == target
  of voNe:
    return v != target
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
    let opStr =
      case c.op
      of voNone: ""
      of voEq: "== "
      of voNe: "!= "
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
        parts.add(
          opStr & (if c.spec.kind == vkSemVer: $c.spec.semver
          else: c.spec.vcsRef)
        )

  result = parts.join(" & ")

proc updateConstraintString*(rawConstraint: string, targetVersionStr: string): string =
  let clean = rawConstraint.strip()
  if clean.startsWith("#"):
    if targetVersionStr.startsWith("#"):
      return targetVersionStr
    else:
      return "#" & targetVersionStr
  try:
    let sem = parseSemVersion(targetVersionStr)
    return updateConstraintString(rawConstraint, sem)
  except ValueError:
    return targetVersionStr
