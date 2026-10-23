import std/[strutils, options]
import types, upstream

const OfficialNimRepoUrl* = "https://github.com/nim-lang/Nim"

proc fetchLatestNimCompilerVersion*(): Option[SemVersion] =
  let tags = fetchUpstreamTags(OfficialNimRepoUrl)
  if tags.len == 0:
    return none(SemVersion)
  # Return highest valid stable release
  for t in tags:
    if t.semver.major > 0 and t.semver.prerelease.len == 0:
      return some(t.semver)
  if tags.len > 0:
    return some(tags[0].semver)
  return none(SemVersion)

proc updateWorkflowNimVersion*(content: string, targetVersion: string): (string, bool) =
  ## Updates nim-version: 'x.y.z' in GitHub Actions workflow content.
  var modified = false
  var lines = content.splitLines()
  for i, line in lines:
    let trimmed = line.strip()
    if trimmed.startsWith("nim-version:"):
      let colonIdx = line.find("nim-version:")
      let indent = line[0..<colonIdx]
      let oldVal = line[(colonIdx + "nim-version:".len)..^1].strip()
      let quoteChar = if oldVal.startsWith("'"): "'" elif oldVal.startsWith("\""): "\"" else: "'"
      let newLine = indent & "nim-version: " & quoteChar & targetVersion & quoteChar
      if line != newLine:
        lines[i] = newLine
        modified = true
  return (lines.join("\n"), modified)

proc updateToolVersionsNim*(content: string, targetVersion: string): (string, bool) =
  ## Updates `nim <version>` in asdf / mise .tool-versions file.
  var modified = false
  var lines = content.splitLines()
  for i, line in lines:
    let parts = line.strip().splitWhitespace()
    if parts.len >= 2 and parts[0] == "nim":
      let newLine = "nim " & targetVersion
      if line.strip() != newLine:
        lines[i] = newLine
        modified = true
  return (lines.join("\n"), modified)

proc updateMiseTomlNim*(content: string, targetVersion: string): (string, bool) =
  ## Updates `nim = "..."` in .mise.toml file.
  var modified = false
  var lines = content.splitLines()
  for i, line in lines:
    let trimmed = line.strip()
    if trimmed.startsWith("nim =") or trimmed.startsWith("nim="):
      let indent = line[0..<line.find("nim")]
      let newLine = indent & "nim = \"" & targetVersion & "\""
      if line != newLine:
        lines[i] = newLine
        modified = true
  return (lines.join("\n"), modified)
