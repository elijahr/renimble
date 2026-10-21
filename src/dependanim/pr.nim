import std/[strutils, options]
import types

proc generateBranchName*(proposals: seq[UpdateProposal], groupName: Option[string] = none(string)): string =
  if groupName.isSome:
    return "dependanim/group-" & groupName.get
  elif proposals.len == 1:
    let p = proposals[0]
    return "dependanim/" & p.dependency.name & "-" & p.targetVersion
  else:
    return "dependanim/updates"

proc generateCommitMessage*(proposals: seq[UpdateProposal], prefix: string = "chore(deps)"): string =
  if proposals.len == 1:
    let p = proposals[0]
    return prefix & ": bump " & p.dependency.name & " from " & p.currentVersion & " to " & p.targetVersion
  else:
    var msg = prefix & ": bump " & $proposals.len & " dependencies\n\n"
    for p in proposals:
      msg.add("- " & p.dependency.name & " from " & p.currentVersion & " to " & p.targetVersion & "\n")
    return msg.strip()

proc generatePrTitle*(proposals: seq[UpdateProposal], groupName: Option[string] = none(string)): string =
  if groupName.isSome:
    return "chore(deps): update " & groupName.get & " group (" & $proposals.len & " packages)"
  elif proposals.len == 1:
    let p = proposals[0]
    return "chore(deps): bump " & p.dependency.name & " from " & p.currentVersion & " to " & p.targetVersion
  else:
    return "chore(deps): bump " & $proposals.len & " dependencies"

proc generatePrBody*(proposals: seq[UpdateProposal]): string =
  result = "Bumps dependencies using **[dependanim](https://github.com/axiomantic/dependanim)**.\n\n"
  result.add("### Updates\n\n")
  result.add("| Package | From | To | Type | Links |\n")
  result.add("|:---|:---|:---|:---|:---|\n")

  for p in proposals:
    let bumpStr = case p.bumpType
      of btMajor: "**Major**"
      of btMinor: "Minor"
      of btPatch: "Patch"
      of btVcs: "VCS Pin"
      of btNone: "None"

    let cl = if p.changelogUrl.isSome: "[Changelog](" & p.changelogUrl.get & ")" else: "-"
    result.add("| `" & p.dependency.name & "` | `" & p.currentVersion & "` | `" & p.targetVersion & "` | " & bumpStr & " | " & cl & " |\n")

  result.add("\n---\n")
  result.add("<details>\n<summary>Dependanim Commands & Options</summary>\n\n")
  result.add("You can trigger Dependanim actions by commenting on this PR:\n")
  result.add("- `@dependanim rebase` will rebase this branch against the target branch\n")
  result.add("- `@dependanim recreate` will recreate this PR and recalculate constraints\n")
  result.add("- `@dependanim close` will close this PR and ignore this version bump\n")
  result.add("</details>\n")
