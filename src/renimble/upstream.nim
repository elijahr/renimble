import std/[osproc, strutils, algorithm, options, os]
import types, version

type UpstreamTag* = object
  name*: string
  semver*: SemVersion
  commitSha*: string

proc parseGitLsRemoteTags*(output: string): seq[UpstreamTag] =
  result = @[]
  for line in output.splitLines():
    let parts = line.split('\t')
    if parts.len == 2:
      let sha = parts[0].strip()
      let refName = parts[1].strip()
      if refName.startsWith("refs/tags/"):
        var tagName = refName["refs/tags/".len..^1]
        # Ignore dereferenced tag pointers ^{} for now or map to same tag
        if tagName.endsWith("^{}"):
          continue
        let sem = parseSemVersion(tagName)
        result.add(UpstreamTag(name: tagName, semver: sem, commitSha: sha))

proc fetchUpstreamTags*(repoUrl: string): seq[UpstreamTag] =
  ## Uses git ls-remote to query available tags and their SHAs without cloning
  result = @[]
  let cmd = "git ls-remote --tags " & quoteShell(repoUrl)
  let (outp, exitCode) = execCmdEx(cmd)
  if exitCode == 0:
    result = parseGitLsRemoteTags(outp)
    # Sort descending by SemVer
    result.sort(proc (a, b: UpstreamTag): int = cmp(b.semver, a.semver))

proc getLatestRelease*(tags: seq[UpstreamTag], currentConstraint: VersionConstraint): Option[UpstreamTag] =
  if tags.len == 0:
    return none(UpstreamTag)

  # Return the highest valid SemVer tag
  for tag in tags:
    if tag.semver.major > 0 or tag.semver.minor > 0 or tag.semver.patch > 0:
      return some(tag)

  return some(tags[0])
