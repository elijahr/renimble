import std/os

proc isGitHubActions*(): bool =
  return getEnv("GITHUB_ACTIONS") == "true"

proc setActionOutput*(name, value: string) =
  let outputFile = getEnv("GITHUB_OUTPUT")
  if outputFile.len > 0:
    try:
      var f = open(outputFile, fmAppend)
      f.writeLine(name & "=" & value)
      f.close()
    except CatchableError:
      discard
  else:
    echo "::set-output name=" & name & "::" & value

proc appendStepSummary*(markdown: string) =
  let summaryFile = getEnv("GITHUB_STEP_SUMMARY")
  if summaryFile.len > 0:
    try:
      var f = open(summaryFile, fmAppend)
      f.writeLine(markdown)
      f.close()
    except CatchableError:
      discard
