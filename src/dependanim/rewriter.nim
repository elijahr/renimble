import std/strutils

proc isRequiresStatement*(s: string): bool =
  let st = s.strip()
  if not st.startsWith("requires"):
    return false
  if st.len == 8:
    return true
  return st[8] in {' ', '\t', '(', '"', '\''}

proc rewriteRequiresLine*(line: string, targetPkg: string, newConstraint: string): string =
  ## Replaces the constraint for targetPkg on a requires line while preserving
  ## surrounding quotes, whitespace, comments, and other packages on the same line.
  let stripped = line.strip()
  if not isRequiresStatement(stripped) and not stripped.contains(targetPkg):
    return line

  result = ""
  var i = 0
  while i < line.len:
    if line[i] in {'"', '\''}:
      let quoteChar = line[i]
      let strStart = i
      inc i
      var strVal = ""
      while i < line.len and line[i] != quoteChar:
        strVal.add(line[i])
        inc i
      if i < line.len and line[i] == quoteChar:
        # We have a full string literal: strVal
        # Check if this string literal references targetPkg
        let trimmedVal = strVal.strip()
        var pkg = ""
        var bracketPart = ""
        var rest = ""

        let bOpen = trimmedVal.find('[')
        let bClose = trimmedVal.find(']')
        if bOpen != -1 and bClose != -1 and bClose > bOpen:
          pkg = trimmedVal[0..<bOpen].strip()
          bracketPart = trimmedVal[bOpen..bClose]
          rest = trimmedVal[(bClose + 1)..^1].strip()
        else:
          var nEnd = 0
          while nEnd < trimmedVal.len and trimmedVal[nEnd] notin {' ', '\t', '#', '=', '<', '>', '^', '~'}:
            inc nEnd
          pkg = trimmedVal[0..<nEnd].strip()
          rest = trimmedVal[nEnd..^1].strip()

        if pkg == targetPkg:
          # Target matched! Replace inside quotes
          var updatedInside = pkg & bracketPart
          if newConstraint.len > 0:
            if not newConstraint.startsWith("#"):
              updatedInside.add(" ")
            updatedInside.add(newConstraint)
          result.add(quoteChar & updatedInside & quoteChar)
        else:
          # Keep original
          result.add(quoteChar & strVal & quoteChar)
        inc i
      else:
        # Unterminated string literal, copy as-is
        result.add(line[strStart..^1])
        break
    else:
      result.add(line[i])
      inc i

proc rewriteNimbleFile*(content: string, targetPkg: string, newConstraint: string): string =
  let lines = content.splitLines()
  var modified: seq[string] = @[]
  var inRequires = false
  var inTripleQuote = false

  for line in lines:
    let count3Q = line.count("\"\"\"")
    if inTripleQuote:
      modified.add(line)
      if count3Q mod 2 != 0:
        inTripleQuote = false
      continue
    elif count3Q mod 2 != 0:
      inTripleQuote = true
      modified.add(line)
      continue

    let stripped = line.strip()
    if isRequiresStatement(stripped) or inRequires:
      if targetPkg in line:
        modified.add(rewriteRequiresLine(line, targetPkg, newConstraint))
      else:
        modified.add(line)

      # Check if continuation ends (line ending with comma outside trailing comments)
      var code = line
      let commentIdx = code.find('#')
      if commentIdx != -1:
        code = code[0..<commentIdx]
      inRequires = code.strip().endsWith(",")
    else:
      modified.add(line)

  result = modified.join("\n")
