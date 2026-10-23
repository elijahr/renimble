import std/[options, tables, strutils]
import types, version, registry, upstream, interval_tree, dismissal, atlas

proc cleanPackageName*(name: string): string =
  if name.startsWith("http://") or name.startsWith("https://") or name.startsWith("git://") or name.startsWith("git@"):
    var clean = name
    if clean.endsWith(".git"):
      clean = clean[0..^5]
    let lastSlash = clean.rfind('/')
    if lastSlash != -1:
      return clean[(lastSlash + 1)..^1]
    return clean
  return name

proc isPackageIgnored*(pkgName: string, ignoreRules: seq[IgnoreRule]): bool =
  let clean = cleanPackageName(pkgName).toLowerAscii()
  for rule in ignoreRules:
    if rule.dependencyName.toLowerAscii() == clean and rule.versions.len == 0:
      return true
  return false

proc isVersionIgnored*(pkgName: string, ver: SemVersion, ignoreRules: seq[IgnoreRule]): bool =
  let clean = cleanPackageName(pkgName).toLowerAscii()
  for rule in ignoreRules:
    if rule.dependencyName.toLowerAscii() == clean:
      if rule.versions.len == 0:
        return true
      var tree = newVersionIntervalTree[string]()
      for vRule in rule.versions:
        let parsed = parseVersionConstraint(vRule)
        for sc in parsed.constraints:
          tree.insert(singleConstraintToInterval(sc), vRule)
      if tree.queryPoint(ver).len > 0:
        return true
  return false

proc findTargetGroup*(depName: string, bump: BumpType, groups: Table[string, GroupConfig]): Option[string] =
  let clean = cleanPackageName(depName)
  for groupName, grp in groups:
    # Check patterns
    for pat in grp.patterns:
      if pat == "*" or pat == clean or pat == depName:
        return some(groupName)
    # Check update types
    for uType in grp.updateTypes:
      if (uType == "major" and bump == btMajor) or
         (uType == "minor" and bump == btMinor) or
         (uType == "patch" and bump == btPatch) or
         (uType == "vcs" and bump == btVcs):
        return some(groupName)
  return none(string)

proc resolveDependencyUpdate*(
  dep: Dependency,
  targetConfig: UpdateTargetConfig,
  reg: PackageRegistry,
  lockFile: Option[LockFile] = none(LockFile),
  atlasConfig: Option[AtlasConfig] = none(AtlasConfig),
  dismissals: seq[string] = @[]
): Option[UpdateProposal] =
  let cleanName = cleanPackageName(dep.name)

  # Don't update "nim" compiler requirement itself unless explicitly configured
  if cleanName.toLowerAscii() == "nim":
    return none(UpdateProposal)

  if isPackageIgnored(cleanName, targetConfig.ignore):
    return none(UpdateProposal)

  # Resolve repository URL:
  var repoUrl = ""

  # 1. Atlas nameOverrides check
  if atlasConfig.isSome and atlasConfig.get.nameOverrides.hasKey(cleanName.toLowerAscii()):
    repoUrl = atlasConfig.get.nameOverrides[cleanName.toLowerAscii()]

  # 2. Lockfile URL check
  if repoUrl.len == 0 and lockFile.isSome and lockFile.get.packages.hasKey(dep.name):
    repoUrl = lockFile.get.packages[dep.name].url

  # 3. Direct URL package check
  if repoUrl.len == 0 and (dep.name.startsWith("http://") or dep.name.startsWith("https://") or dep.name.startsWith("git://") or dep.name.startsWith("git@")):
    repoUrl = dep.name

  # 4. Registry packages.json check
  if repoUrl.len == 0:
    let regPkg = reg.findPackage(cleanName)
    if regPkg.isSome:
      repoUrl = regPkg.get.url

  if repoUrl.len == 0:
    return none(UpdateProposal)

  # ---------------------------------------------------------------------------
  # Handle Commit Hash Pins (#sha)
  # ---------------------------------------------------------------------------
  if dep.constraint.constraints.len == 1 and dep.constraint.constraints[0].spec.kind == vkCommit:
    let currentSha = dep.constraint.constraints[0].spec.vcsRef
    let remoteHeadOpt = fetchRemoteHeadCommit(repoUrl)
    if remoteHeadOpt.isSome:
      let latestSha = remoteHeadOpt.get
      if latestSha.toLowerAscii() != currentSha.toLowerAscii():
        let shortCurrent = if currentSha.len >= 8: currentSha[0..<8] else: currentSha
        let shortTarget = if latestSha.len >= 8: latestSha[0..<8] else: latestSha
        
        # Check dismissal
        if isVersionDismissed(cleanName, shortTarget, dismissals):
          return none(UpdateProposal)

        let grp = findTargetGroup(cleanName, btVcs, targetConfig.groups)
        return some(UpdateProposal(
          dependency: dep,
          currentVersion: shortCurrent,
          targetVersion: shortTarget,
          targetVcsRevision: latestSha,
          bumpType: btVcs,
          groupName: grp,
          changelogUrl: some(repoUrl & "/commits"),
          isLockfileOnly: false
        ))
    return none(UpdateProposal)

  # ---------------------------------------------------------------------------
  # Handle SemVer Tag Releases
  # ---------------------------------------------------------------------------
  let tags = fetchUpstreamTags(repoUrl)
  let latestOpt = getLatestRelease(tags, dep.constraint)
  if latestOpt.isNone:
    return none(UpdateProposal)

  let latest = latestOpt.get
  if isVersionIgnored(cleanName, latest.semver, targetConfig.ignore):
    return none(UpdateProposal)

  # Check closed PR dismissal memory ("ok I won't notify you again")
  if isVersionDismissed(cleanName, $latest.semver, dismissals):
    return none(UpdateProposal)

  var curVersion = SemVersion()
  var hasCurVersion = false
  # Derive current version from lockfile or constraint
  if lockFile.isSome and lockFile.get.packages.hasKey(dep.name):
    try:
      curVersion = parseSemVersion(lockFile.get.packages[dep.name].version)
      hasCurVersion = true
    except ValueError:
      discard

  if not hasCurVersion:
    for c in dep.constraint.constraints:
      if c.spec.kind == vkSemVer:
        curVersion = c.spec.semver
        hasCurVersion = true
        break

  let bump = getBumpType(curVersion, latest.semver)
  if bump == btNone:
    return none(UpdateProposal)

  # Determine if this update is in-range (lockfile-only) or out-of-range (manifest bump)
  var isLockOnly = false
  if lockFile.isSome and latest.semver.satisfies(dep.constraint):
    isLockOnly = true

  let grp = findTargetGroup(cleanName, bump, targetConfig.groups)

  result = some(UpdateProposal(
    dependency: dep,
    currentVersion: $curVersion,
    targetVersion: $latest.semver,
    targetVcsRevision: latest.commitSha,
    bumpType: bump,
    groupName: grp,
    changelogUrl: some(repoUrl & "/releases"),
    isLockfileOnly: isLockOnly
  ))
