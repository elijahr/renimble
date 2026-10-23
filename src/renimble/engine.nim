import std/[options, tables, strutils]
import types, version, registry, upstream, interval_tree

proc isPackageIgnored*(pkgName: string, ignoreRules: seq[IgnoreRule]): bool =
  for rule in ignoreRules:
    if rule.dependencyName.toLowerAscii() == pkgName.toLowerAscii() and rule.versions.len == 0:
      return true
  return false

proc isVersionIgnored*(pkgName: string, ver: SemVersion, ignoreRules: seq[IgnoreRule]): bool =
  for rule in ignoreRules:
    if rule.dependencyName.toLowerAscii() == pkgName.toLowerAscii():
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
  for groupName, grp in groups:
    # Check patterns
    for pat in grp.patterns:
      if pat == "*" or pat == depName:
        return some(groupName)
    # Check update types
    for uType in grp.updateTypes:
      if (uType == "major" and bump == btMajor) or
         (uType == "minor" and bump == btMinor) or
         (uType == "patch" and bump == btPatch):
        return some(groupName)
  return none(string)

proc resolveDependencyUpdate*(
  dep: Dependency,
  targetConfig: UpdateTargetConfig,
  reg: PackageRegistry,
  lockFile: Option[LockFile]
): Option[UpdateProposal] =
  # Don't update "nim" compiler requirement itself unless explicitly configured
  if dep.name.toLowerAscii() == "nim":
    return none(UpdateProposal)

  if isPackageIgnored(dep.name, targetConfig.ignore):
    return none(UpdateProposal)

  var repoUrl = ""
  if lockFile.isSome and lockFile.get.packages.hasKey(dep.name):
    repoUrl = lockFile.get.packages[dep.name].url

  if repoUrl.len == 0:
    let regPkg = reg.findPackage(dep.name)
    if regPkg.isSome:
      repoUrl = regPkg.get.url

  if repoUrl.len == 0:
    return none(UpdateProposal)

  let tags = fetchUpstreamTags(repoUrl)
  let latestOpt = getLatestRelease(tags, dep.constraint)
  if latestOpt.isNone:
    return none(UpdateProposal)

  let latest = latestOpt.get
  if isVersionIgnored(dep.name, latest.semver, targetConfig.ignore):
    return none(UpdateProposal)

  var curVersion = SemVersion()
  # Derive current version from lockfile or constraint
  if lockFile.isSome and lockFile.get.packages.hasKey(dep.name):
    curVersion = parseSemVersion(lockFile.get.packages[dep.name].version)
  else:
    for c in dep.constraint.constraints:
      if c.spec.kind == vkSemVer:
        curVersion = c.spec.semver
        break

  let bump = getBumpType(curVersion, latest.semver)
  if bump == btNone:
    return none(UpdateProposal)

  let grp = findTargetGroup(dep.name, bump, targetConfig.groups)

  result = some(UpdateProposal(
    dependency: dep,
    currentVersion: $curVersion,
    targetVersion: $latest.semver,
    targetVcsRevision: latest.commitSha,
    bumpType: bump,
    groupName: grp,
    changelogUrl: some(repoUrl & "/releases")
  ))
