import std/[os, osproc, json, strutils]

const LocalDismissedFile* = ".renimble/dismissed.json"

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
        
        # If closed without being merged, the user rejected/dismissed it!
        if not isMerged and pr.hasKey("headRefName"):
          let branch = pr["headRefName"].getStr()
          if branch.startsWith("renimble/"):
            result.add(branch)
  except CatchableError:
    discard

proc loadLocalDismissals*(dir: string = "."): seq[string] =
  result = @[]
  let path = dir / LocalDismissedFile
  if fileExists(path):
    try:
      let j = parseJson(readFile(path))
      if j.kind == JArray:
        for item in j:
          if item.kind == JString:
            result.add(item.getStr())
    except CatchableError:
      discard

proc recordLocalDismissal*(branchOrTag: string, dir: string = ".") =
  let path = dir / LocalDismissedFile
  var existing = loadLocalDismissals(dir)
  if branchOrTag notin existing:
    existing.add(branchOrTag)
    try:
      createDir(dir / ".renimble")
      var j = newJArray()
      for b in existing:
        j.add(%b)
      writeFile(path, pretty(j, indent = 2) & "\n")
    except CatchableError:
      discard

proc fetchClosedPrDismissals*(workingDir: string = ""): seq[string] =
  ## Queries gh CLI if available for closed unmerged PRs, unioned with local dismissals.
  result = loadLocalDismissals(if workingDir.len > 0: workingDir else: ".")

  let cmd = "gh pr list --state closed --json headRefName,mergedAt --limit 100"
  let (outp, exitCode) = execCmdEx(cmd)
  if exitCode == 0 and outp.len > 0:
    let fromGh = parseGhClosedPrs(outp)
    for b in fromGh:
      if b notin result:
        result.add(b)

proc isVersionDismissed*(pkgName: string, targetVersion: string, dismissals: seq[string]): bool =
  ## Returns true if a PR for this exact version was closed without merging.
  let targetBranch = "renimble/" & pkgName & "-" & targetVersion
  let targetTag = pkgName & ":" & targetVersion
  for d in dismissals:
    if d == targetBranch or d == targetTag:
      return true
  return false
