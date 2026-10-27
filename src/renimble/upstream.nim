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
        var tagName = refName["refs/tags/".len ..^ 1]
        # Ignore dereferenced tag pointers ^{} for now or map to same tag
        if tagName.endsWith("^{}"):
          continue
        try:
          let sem = parseSemVersion(tagName)
          result.add(UpstreamTag(name: tagName, semver: sem, commitSha: sha))
        except ValueError:
          # Safely ignore non-SemVer tags like 'nightly', 'devel', 'v_old'
          discard

proc fetchUpstreamTags*(repoUrl: string): seq[UpstreamTag] =
  ## Uses git ls-remote to query available tags and their SHAs without cloning
  result = @[]
  let cmd = "git ls-remote --tags " & quoteShell(repoUrl)
  let (outp, exitCode) = execCmdEx(cmd)
  if exitCode == 0:
    result = parseGitLsRemoteTags(outp)
    # Sort descending by SemVer
    result.sort(
      proc(a, b: UpstreamTag): int =
        cmp(b.semver, a.semver)
    )

proc getLatestRelease*(
    tags: seq[UpstreamTag], currentConstraint: VersionConstraint
): Option[UpstreamTag] =
  if tags.len == 0:
    return none(UpstreamTag)

  # Check if current constraint allows or specifies a prerelease
  var allowPrerelease = false
  for c in currentConstraint.constraints:
    if c.spec.kind == vkSemVer and c.spec.semver.prerelease.len > 0:
      allowPrerelease = true
      break

  # 1. If tracking prereleases, return the absolute highest tag
  if allowPrerelease:
    for tag in tags:
      if tag.semver.major > 0 or tag.semver.minor > 0 or tag.semver.patch > 0:
        return some(tag)
    return some(tags[0])

  # 2. For stable tracking, prefer highest stable release (no prerelease identifier)
  for tag in tags:
    if tag.semver.prerelease.len == 0:
      if tag.semver.major > 0 or tag.semver.minor > 0 or tag.semver.patch > 0:
        return some(tag)

  # 3. Fallback to highest tag if no stable releases exist
  for tag in tags:
    if tag.semver.major > 0 or tag.semver.minor > 0 or tag.semver.patch > 0:
      return some(tag)

  return some(tags[0])

proc fetchRemoteHeadCommit*(repoUrl: string): Option[string] =
  ## Queries git ls-remote to find the commit SHA of the default branch / HEAD
  let cmd = "git ls-remote " & quoteShell(repoUrl) & " HEAD"
  let (outp, exitCode) = execCmdEx(cmd)
  if exitCode == 0:
    for line in outp.splitLines():
      let parts = line.split('\t')
      if parts.len == 2:
        let sha = parts[0].strip()
        if sha.len >= 7:
          return some(sha)
  return none(string)
