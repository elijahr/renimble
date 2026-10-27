import std/[os, osproc, json, strutils]

const MetadataStartTag = "<!-- renimble-metadata"
const MetadataEndTag = "-->"

proc extractMetadataFromPrBody*(body: string): seq[string] =
  result = @[]
  let startIdx = body.find(MetadataStartTag)
  if startIdx == -1:
    return
  let afterStart = body[(startIdx + MetadataStartTag.len) ..^ 1]
  let endIdx = afterStart.find(MetadataEndTag)
  if endIdx == -1:
    return
  let jsonStr = afterStart[0 ..< endIdx].strip()
  try:
    let j = parseJson(jsonStr)
    if j.kind == JObject and j.hasKey("proposals") and j["proposals"].kind == JArray:
      for p in j["proposals"]:
        if p.hasKey("package") and p.hasKey("targetVersion"):
          let pkg = p["package"].getStr()
          let ver = p["targetVersion"].getStr()
          result.add(pkg & ":" & ver)
          result.add("renimble/" & pkg & "-" & ver)
  except CatchableError:
    discard

proc parseGhClosedPrs*(jsonOutput: string): seq[string] =
  result = @[]
  try:
    let j = parseJson(jsonOutput)
    if j.kind == JArray:
      for pr in j:
        var isMerged = false
        if pr.hasKey("mergedAt"):
          let m = pr["mergedAt"]
          if m.kind == JString and m.getStr().len > 0:
            isMerged = true

        # If closed without being merged, it was dismissed!
        if not isMerged:
          # 1. Check structured hidden metadata in PR body (Primary)
          if pr.hasKey("body") and pr["body"].kind == JString:
            let fromBody = extractMetadataFromPrBody(pr["body"].getStr())
            for item in fromBody:
              if item notin result:
                result.add(item)

          # 2. Check head branch name (Fallback)
          if pr.hasKey("headRefName") and pr["headRefName"].kind == JString:
            let branch = pr["headRefName"].getStr()
            if branch.startsWith("renimble/") and branch notin result:
              result.add(branch)
  except CatchableError:
    discard

proc getDismissalsCachePath*(overrideDir: string = ""): string =
  if overrideDir.len > 0:
    return overrideDir / "dismissals.json"
  return getCacheDir("renimble") / "dismissals.json"

proc loadLocalDismissals*(cacheDirOverride: string = ""): seq[string] =
  result = @[]
  let path = getDismissalsCachePath(cacheDirOverride)
  if fileExists(path):
    try:
      let j = parseJson(readFile(path))
      if j.kind == JArray:
        for item in j:
          if item.kind == JString:
            result.add(item.getStr())
    except CatchableError:
      discard

proc recordLocalDismissal*(branchOrTag: string, cacheDirOverride: string = "") =
  let path = getDismissalsCachePath(cacheDirOverride)
  var existing = loadLocalDismissals(cacheDirOverride)
  if branchOrTag notin existing:
    existing.add(branchOrTag)
    try:
      createDir(splitFile(path).dir)
      var j = newJArray()
      for b in existing:
        j.add(%b)
      writeFile(path, pretty(j, indent = 2) & "\n")
    except CatchableError:
      discard

proc fetchClosedPrDismissals*(cacheDirOverride: string = ""): seq[string] =
  ## Queries gh CLI for closed unmerged PRs (reading headRefName, mergedAt, and body),
  ## unioned with any locally cached user dismissals.
  result = loadLocalDismissals(cacheDirOverride)

  let cmd = "gh pr list --state closed --json headRefName,mergedAt,body --limit 100"
  let (outp, exitCode) = execCmdEx(cmd)
  if exitCode == 0 and outp.len > 0:
    let fromGh = parseGhClosedPrs(outp)
    for b in fromGh:
      if b notin result:
        result.add(b)

proc isVersionDismissed*(
    pkgName: string, targetVersion: string, dismissals: seq[string]
): bool =
  ## Returns true if a PR for this exact version was closed without merging.
  let targetBranch = "renimble/" & pkgName & "-" & targetVersion
  let targetTag = pkgName & ":" & targetVersion
  for d in dismissals:
    if d == targetBranch or d == targetTag:
      return true
  return false
