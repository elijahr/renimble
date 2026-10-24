import std/[strutils, options]
import types, version

proc cleanPackageName*(name: string): string =
  ## Strips URL schemes, forge prefixes, and trailing .git extensions to produce a canonical package name.
  if name.startsWith("http://") or name.startsWith("https://") or name.startsWith("git://") or name.startsWith("git@"):
    var clean = name
    if clean.endsWith(".git"):
      clean = clean[0..^5]
    let lastSlash = clean.rfind('/')
    if lastSlash != -1:
      return clean[(lastSlash + 1)..^1]
    return clean
  return name

proc parseRequiresArg(rawArg: string, lineIndex: int, rawLine: string): Option[Dependency] =
  var clean = rawArg.strip()
  if clean.startsWith("\"") and clean.endsWith("\"") and clean.len >= 2:
    clean = clean[1..^2]
  elif clean.startsWith("'") and clean.endsWith("'") and clean.len >= 2:
    clean = clean[1..^2]
  else:
    return none(Dependency)

  clean = clean.strip()
  if clean.len == 0:
    return none(Dependency)

  # Check for feature flag: pkg[feature] >= 1.0
  var pkgName = ""
  var feature: Option[string] = none(string)
  var rest = ""

  let bracketOpen = clean.find('[')
  let bracketClose = clean.find(']')
  if bracketOpen != -1 and bracketClose != -1 and bracketClose > bracketOpen:
    pkgName = clean[0..<bracketOpen].strip()
    feature = some(clean[(bracketOpen + 1)..<bracketClose].strip())
    rest = clean[(bracketClose + 1)..^1].strip()
  else:
    # Separate package name from constraint
    # Package name ends at whitespace or special character (#, =, <, >, ^, ~)
    var nameEnd = 0
    while nameEnd < clean.len and clean[nameEnd] notin {' ', '\t', '#', '=', '<', '>', '^', '~'}:
      inc nameEnd
    pkgName = clean[0..<nameEnd].strip()
    rest = clean[nameEnd..^1].strip()

  let constraint = parseVersionConstraint(rest)

  result = some(Dependency(
    name: pkgName,
    rawConstraint: rest,
    constraint: constraint,
    feature: feature,
    rawLine: rawLine,
    lineIndex: lineIndex
  ))

proc isRequiresStatement*(s: string): bool =
  let st = s.strip()
  if not st.startsWith("requires"):
    return false
  if st.len == 8:
    return true
  return st[8] in {' ', '\t', '(', '"', '\''}

proc parseNimbleManifest*(content: string, filePath: string = ""): NimbleManifest =
  result.filePath = filePath
  let lines = content.splitLines()
  var inRequiresContinuation = false
  var inTripleQuote = false

  for i, line in lines:
    let count3Q = line.count("\"\"\"")
    if inTripleQuote:
      if count3Q mod 2 != 0:
        inTripleQuote = false
      continue
    elif count3Q mod 2 != 0:
      inTripleQuote = true
      continue

    let stripped = line.strip()
    if stripped.len == 0:
      continue
    # Skip full comment lines
    if stripped.startsWith("#"):
      continue

    # Extract metadata fields
    if stripped.startsWith("version"):
      inRequiresContinuation = false
      let eqIdx = stripped.find('=')
      if eqIdx != -1:
        result.version = stripped[(eqIdx + 1)..^1].strip().strip(chars = {'"'})
    elif stripped.startsWith("author"):
      inRequiresContinuation = false
      let eqIdx = stripped.find('=')
      if eqIdx != -1:
        result.author = stripped[(eqIdx + 1)..^1].strip().strip(chars = {'"'})
    elif stripped.startsWith("description"):
      inRequiresContinuation = false
      let eqIdx = stripped.find('=')
      if eqIdx != -1:
        result.description = stripped[(eqIdx + 1)..^1].strip().strip(chars = {'"'})
    elif stripped.startsWith("license"):
      inRequiresContinuation = false
      let eqIdx = stripped.find('=')
      if eqIdx != -1:
        result.license = stripped[(eqIdx + 1)..^1].strip().strip(chars = {'"'})

    # Extract requires lines or continuations
    if isRequiresStatement(stripped) or inRequiresContinuation:
      let toParse = if isRequiresStatement(stripped): stripped[8..^1].strip() else: stripped
      var currentArg = ""
      var inQuote = false
      var quoteChar = '"'
      var lineEndsWithComma = false

      for ch in toParse:
        if ch in {'"', '\''}:
          if not inQuote:
            inQuote = true
            quoteChar = ch
          elif quoteChar == ch:
            inQuote = false
          currentArg.add(ch)
          lineEndsWithComma = false
        elif ch == '#' and not inQuote:
          # Trailing comment reached
          break
        elif ch == ',' and not inQuote:
          let depOpt = parseRequiresArg(currentArg, i, line)
          if depOpt.isSome:
            result.dependencies.add(depOpt.get)
          currentArg = ""
          lineEndsWithComma = true
        elif ch in {' ', '\t'}:
          if inQuote:
            currentArg.add(ch)
        else:
          currentArg.add(ch)
          lineEndsWithComma = false

      if currentArg.len > 0:
        let depOpt = parseRequiresArg(currentArg, i, line)
        if depOpt.isSome:
          result.dependencies.add(depOpt.get)

      inRequiresContinuation = lineEndsWithComma
