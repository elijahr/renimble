import std/[unittest, tables]
import ../src/renimble/[types, config]

suite "Renimble Configuration Parser":
  test "Parse sample renimble.yml":
    let yamlContent = """
version: 1
updates:
  - package-ecosystem: "nimble"
    directory: "/"
    target-branch: "main"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "06:00"
      timezone: "Etc/UTC"
    groups:
      dev-deps:
        patterns:
          - "testutils"
          - "unittest2"
    ignore:
      - dependency-name: "chronos"
    commit-message:
      prefix: "chore(deps)"
      include: "scope"
    labels:
      - "dependencies"
      - "nim"
    open-pull-requests-limit: 5
"""
    let conf = parseSimpleYamlConfig(yamlContent)
    check conf.version == 1
    check conf.updates.len == 1
    let u = conf.updates[0]
    check u.packageEcosystem == "nimble"
    check u.directory == "/"
    check u.targetBranch == "main"
    check u.schedule.interval == siWeekly
    check u.groups.hasKey("dev-deps")
    check u.groups["dev-deps"].patterns == @["testutils", "unittest2"]
    check u.ignore.len == 1
    check u.ignore[0].dependencyName == "chronos"
    check u.commitMessage.prefix == "chore(deps)"
    check u.labels == @["dependencies", "nim"]
    check u.openPullRequestsLimit == 5
