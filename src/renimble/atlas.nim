import std/[os, json, tables, options, strutils]

type
  AtlasConfig* = object
    deps*: string
    nameOverrides*: Table[string, string]

  AtlasLockPackage* = object
    url*: string
    commit*: string
    version*: string

  AtlasLock* = object
    filePath*: string
    packages*: Table[string, AtlasLockPackage]

proc findAtlasConfigFile*(dir: string = "."): Option[string] =
  let rootConfig = dir / "atlas.config"
  if fileExists(rootConfig):
    return some(rootConfig)
  let depsConfig = dir / "deps" / "atlas.config"
  if fileExists(depsConfig):
    return some(depsConfig)
  let subDepsConfig = dir / "_deps" / "atlas.config"
  if fileExists(subDepsConfig):
    return some(subDepsConfig)
  return none(string)

proc isAtlasWorkspace*(dir: string = "."): bool =
  if findAtlasConfigFile(dir).isSome:
    return true
  if fileExists(dir / "atlas.lock"):
    return true
  return false

proc parseAtlasConfig*(content: string): AtlasConfig =
  result.deps = "deps"
  result.nameOverrides = initTable[string, string]()
  try:
    let j = parseJson(content)
    if j.kind == JObject:
      if j.hasKey("deps") and j["deps"].kind == JString:
        result.deps = j["deps"].getStr()
      if j.hasKey("nameOverrides") and j["nameOverrides"].kind == JObject:
        for k, v in j["nameOverrides"].pairs:
          if v.kind == JString:
            result.nameOverrides[k.toLowerAscii()] = v.getStr()
  except CatchableError:
    discard

proc loadAtlasConfig*(dir: string = "."): Option[AtlasConfig] =
  let pathOpt = findAtlasConfigFile(dir)
  if pathOpt.isSome:
    let content = readFile(pathOpt.get)
    return some(parseAtlasConfig(content))
  return none(AtlasConfig)

proc parseAtlasLock*(content: string, filePath: string = "atlas.lock"): AtlasLock =
  result.filePath = filePath
  result.packages = initTable[string, AtlasLockPackage]()
  if content.strip().len == 0:
    return

  # First attempt JSON parse
  try:
    let j = parseJson(content)
    if j.kind == JObject:
      for pkgName, pkgNode in j.pairs:
        if pkgNode.kind == JObject:
          var lp = AtlasLockPackage()
          if pkgNode.hasKey("url"):
            lp.url = pkgNode["url"].getStr()
          if pkgNode.hasKey("commit"):
            lp.commit = pkgNode["commit"].getStr()
          if pkgNode.hasKey("version"):
            lp.version = pkgNode["version"].getStr()
          result.packages[pkgName] = lp
      return
  except CatchableError:
    discard

  # Fallback to key-value line parse:
  # package=commit or package URL commit
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue
    let parts = trimmed.splitWhitespace()
    if parts.len >= 2:
      let name = parts[0]
      let commit = parts[^1]
      let url =
        if parts.len >= 3:
          parts[1]
        else:
          ""
      result.packages[name] = AtlasLockPackage(url: url, commit: commit, version: "")

proc loadAtlasLock*(path: string = "atlas.lock"): Option[AtlasLock] =
  if fileExists(path):
    let content = readFile(path)
    return some(parseAtlasLock(content, path))
  return none(AtlasLock)

proc serializeAtlasLock*(lock: AtlasLock): string =
  var j = newJObject()
  for name, pkg in lock.packages:
    var pNode = newJObject()
    pNode["url"] = %pkg.url
    pNode["commit"] = %pkg.commit
    if pkg.version.len > 0:
      pNode["version"] = %pkg.version
    j[name] = pNode
  return pretty(j, indent = 2) & "\n"

proc updateAtlasLock*(
    lock: var AtlasLock,
    pkgName: string,
    commit: string,
    version: string = "",
    url: string = "",
) =
  if lock.packages.hasKey(pkgName):
    var p = lock.packages[pkgName]
    p.commit = commit
    if version.len > 0:
      p.version = version
    if url.len > 0:
      p.url = url
    lock.packages[pkgName] = p
  else:
    lock.packages[pkgName] =
      AtlasLockPackage(url: url, commit: commit, version: version)
