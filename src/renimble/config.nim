import std/[strutils, tables, os]
import types

proc defaultTargetConfig*(): UpdateTargetConfig =
  result = UpdateTargetConfig(
    packageEcosystem: "nimble",
    directory: "/",
    targetBranch: "main",
    schedule: ScheduleConfig(
      interval: siWeekly,
      day: "monday",
      time: "06:00",
      timezone: "Etc/UTC"
    ),
    groups: initTable[string, GroupConfig](),
    ignore: @[],
    commitMessage: CommitMessageConfig(
      prefix: "chore(deps)",
      includeScope: true
    ),
    labels: @["dependencies", "nim"],
    reviewers: @[],
    assignees: @[],
    openPullRequestsLimit: 10,
    updateCompilerRequirement: false
  )

proc parseSimpleYamlConfig*(content: string): RenimbleConfig =
  ## Parses .github/renimble.yml using a resilient, dependency-free line parser.
  result = RenimbleConfig(version: 1, updates: @[])
  var currentTarget = defaultTargetConfig()
  var hasTarget = false

  var currentSection = ""
  var currentGroupName = ""

  for rawLine in content.splitLines():
    let trimmed = rawLine.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue

    let indent = rawLine.len - rawLine.strip(leading = true, trailing = false).len

    if trimmed.startsWith("version:"):
      let val = trimmed[8..^1].strip()
      try:
        result.version = parseInt(val)
      except CatchableError:
        result.version = 1
      continue

    if trimmed.startsWith("- package-ecosystem:") or (trimmed.startsWith("package-ecosystem:") and indent <= 4):
      if hasTarget:
        result.updates.add(currentTarget)
      currentTarget = defaultTargetConfig()
      hasTarget = true
      let val = trimmed.split(':')[1].strip().strip(chars = {'"', '\''})
      currentTarget.packageEcosystem = val
      currentSection = ""
      continue

    if trimmed.startsWith("directory:"):
      currentTarget.directory = trimmed[10..^1].strip().strip(chars = {'"', '\''})
    elif trimmed.startsWith("target-branch:"):
      currentTarget.targetBranch = trimmed[14..^1].strip().strip(chars = {'"', '\''})
    elif trimmed.startsWith("schedule:"):
      currentSection = "schedule"
    elif trimmed.startsWith("groups:"):
      currentSection = "groups"
    elif trimmed.startsWith("ignore:"):
      currentSection = "ignore"
      currentTarget.ignore = @[]
    elif trimmed.startsWith("commit-message:"):
      currentSection = "commit-message"
    elif trimmed.startsWith("labels:"):
      currentSection = "labels"
      currentTarget.labels = @[]
    elif trimmed.startsWith("reviewers:"):
      currentSection = "reviewers"
      currentTarget.reviewers = @[]
    elif trimmed.startsWith("assignees:"):
      currentSection = "assignees"
      currentTarget.assignees = @[]
    elif trimmed.startsWith("open-pull-requests-limit:"):
      try:
        currentTarget.openPullRequestsLimit = parseInt(trimmed[25..^1].strip())
      except CatchableError:
        discard
    elif trimmed.startsWith("update-compiler-requirement:"):
      let v = trimmed[27..^1].strip().toLowerAscii()
      currentTarget.updateCompilerRequirement = (v == "true" or v == "yes")
    elif currentSection == "schedule":
      if trimmed.startsWith("interval:"):
        let iv = trimmed[9..^1].strip().toLowerAscii()
        if iv == "daily":
          currentTarget.schedule.interval = siDaily
        elif iv == "monthly":
          currentTarget.schedule.interval = siMonthly
        else:
          currentTarget.schedule.interval = siWeekly
      elif trimmed.startsWith("day:"):
        currentTarget.schedule.day = trimmed[4..^1].strip()
      elif trimmed.startsWith("time:"):
        currentTarget.schedule.time = trimmed[5..^1].strip()
      elif trimmed.startsWith("timezone:"):
        currentTarget.schedule.timezone = trimmed[9..^1].strip()
    elif currentSection == "commit-message":
      if trimmed.startsWith("prefix:"):
        currentTarget.commitMessage.prefix = trimmed[7..^1].strip().strip(chars = {'"', '\''})
      elif trimmed.startsWith("include:"):
        currentTarget.commitMessage.includeScope = (trimmed[8..^1].strip() == "scope")
    elif currentSection == "labels":
      if trimmed.startsWith("-"):
        let lbl = trimmed[1..^1].strip().strip(chars = {'"', '\''})
        currentTarget.labels.add(lbl)
    elif currentSection == "reviewers":
      if trimmed.startsWith("-"):
        currentTarget.reviewers.add(trimmed[1..^1].strip().strip(chars = {'"', '\''}))
    elif currentSection == "assignees":
      if trimmed.startsWith("-"):
        currentTarget.assignees.add(trimmed[1..^1].strip().strip(chars = {'"', '\''}))
    elif currentSection == "groups":
      if indent == 6 or (indent == 4 and trimmed.endsWith(":")):
        currentGroupName = trimmed[0..^2].strip()
        currentTarget.groups[currentGroupName] = GroupConfig(patterns: @[], updateTypes: @[])
      elif currentGroupName.len > 0:
        if trimmed.startsWith("-"):
          let pat = trimmed[1..^1].strip().strip(chars = {'"', '\''})
          var grp = currentTarget.groups[currentGroupName]
          grp.patterns.add(pat)
          currentTarget.groups[currentGroupName] = grp
    elif currentSection == "ignore":
      if trimmed.startsWith("dependency-name:") or trimmed.startsWith("- dependency-name:"):
        let dep = trimmed.split(':')[1].strip().strip(chars = {'"', '\''})
        currentTarget.ignore.add(IgnoreRule(dependencyName: dep, versions: @[]))

  if hasTarget:
    result.updates.add(currentTarget)
  elif result.updates.len == 0:
    # If no explicit updates section, provide default target
    result.updates.add(defaultTargetConfig())

proc loadConfig*(path: string): RenimbleConfig =
  if fileExists(path):
    let content = readFile(path)
    result = parseSimpleYamlConfig(content)
  else:
    result = RenimbleConfig(version: 1, updates: @[defaultTargetConfig()])
