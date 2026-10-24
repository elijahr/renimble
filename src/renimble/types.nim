import std/[options, tables]

type
  VersionOp* = enum
    voNone,      # No operator (exact or untyped)
    voEq,        # ==
    voNe,        # !=
    voLt,        # <
    voLe,        # <=
    voGt,        # >
    voGe,        # >=
    voCaret,     # ^=
    voTilde      # ~=

  VersionKind* = enum
    vkSemVer,    # 1.2.3
    vkHead,      # #head
    vkBranch,    # #master
    vkCommit     # #sha

  SemVersion* = object
    major*: int
    minor*: int
    patch*: int
    prerelease*: string
    build*: string

  VersionSpec* = object
    kind*: VersionKind
    semver*: SemVersion
    vcsRef*: string

  SingleConstraint* = object
    op*: VersionOp
    spec*: VersionSpec

  VersionConstraint* = object
    isAny*: bool
    constraints*: seq[SingleConstraint] # Intersected with '&'

  Dependency* = object
    name*: string
    rawConstraint*: string
    constraint*: VersionConstraint
    feature*: Option[string]
    rawLine*: string
    lineIndex*: int # 0-indexed line number in source file

  NimbleManifest* = object
    filePath*: string
    name*: string
    version*: string
    author*: string
    description*: string
    license*: string
    dependencies*: seq[Dependency]

  LockPackage* = object
    version*: string
    vcsRevision*: string
    url*: string
    downloadMethod*: string
    dependencies*: seq[string]

  LockFile* = object
    filePath*: string
    version*: int
    packages*: Table[string, LockPackage]

  ScheduleInterval* = enum
    siDaily,
    siWeekly,
    siMonthly

  ScheduleConfig* = object
    interval*: ScheduleInterval
    day*: string
    time*: string
    timezone*: string

  GroupConfig* = object
    patterns*: seq[string]
    updateTypes*: seq[string] # "major", "minor", "patch"

  IgnoreRule* = object
    dependencyName*: string
    versions*: seq[string]

  CommitMessageConfig* = object
    prefix*: string
    includeScope*: bool

  UpdateTargetConfig* = object
    packageEcosystem*: string
    directory*: string
    targetBranch*: string
    schedule*: ScheduleConfig
    groups*: Table[string, GroupConfig]
    ignore*: seq[IgnoreRule]
    commitMessage*: CommitMessageConfig
    labels*: seq[string]
    reviewers*: seq[string]
    assignees*: seq[string]
    openPullRequestsLimit*: int
    updateCompilerRequirement*: bool

  RenimbleConfig* = object
    version*: int
    updates*: seq[UpdateTargetConfig]

  BumpType* = enum
    btNone,
    btPatch,
    btMinor,
    btMajor,
    btVcs

  UpdateProposal* = object
    dependency*: Dependency
    currentVersion*: string
    targetVersion*: string
    targetVcsRevision*: string
    bumpType*: BumpType
    groupName*: Option[string]
    changelogUrl*: Option[string]
    isLockfileOnly*: bool

  RegistryPackage* = object
    name*: string
    url*: string
    downloadMethod*: string
    tags*: seq[string]
    description*: string
    license*: string
    web*: string
