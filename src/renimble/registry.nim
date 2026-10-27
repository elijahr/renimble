import std/[httpclient, json, os, tables, options, strutils]
import types

const DefaultRegistryUrl* =
  "https://raw.githubusercontent.com/nim-lang/packages/master/packages.json"

type PackageRegistry* = object
  packages*: Table[string, RegistryPackage]
  cachePath*: string

proc newPackageRegistry*(cacheDir: string = ""): PackageRegistry =
  let actualDir =
    if cacheDir.len > 0:
      cacheDir
    else:
      getCacheDir("renimble")
  createDir(actualDir)
  result.cachePath = actualDir / "packages.json"
  result.packages = initTable[string, RegistryPackage]()

proc loadFromContent*(reg: var PackageRegistry, content: string) =
  let jnode = parseJson(content)
  if jnode.kind == JArray:
    for item in jnode:
      var pkg = RegistryPackage()
      if item.hasKey("name"):
        pkg.name = item["name"].getStr()
      if item.hasKey("url"):
        pkg.url = item["url"].getStr()
      if item.hasKey("method"):
        pkg.downloadMethod = item["method"].getStr()
      if item.hasKey("description"):
        pkg.description = item["description"].getStr()
      if item.hasKey("license"):
        pkg.license = item["license"].getStr()
      if item.hasKey("web"):
        pkg.web = item["web"].getStr()
      if item.hasKey("tags") and item["tags"].kind == JArray:
        for t in item["tags"]:
          pkg.tags.add(t.getStr())

      if pkg.name.len > 0:
        reg.packages[pkg.name.toLowerAscii()] = pkg

proc fetchRegistry*(
    reg: var PackageRegistry,
    forceRefresh: bool = false,
    url: string = DefaultRegistryUrl,
): bool =
  if not forceRefresh and fileExists(reg.cachePath):
    try:
      let content = readFile(reg.cachePath)
      reg.loadFromContent(content)
      return true
    except CatchableError:
      discard

  try:
    var client = newHttpClient(timeout = 10000)
    try:
      let body = client.getContent(url)
      writeFile(reg.cachePath, body)
      reg.loadFromContent(body)
      return true
    finally:
      client.close()
  except CatchableError:
    if fileExists(reg.cachePath):
      try:
        let content = readFile(reg.cachePath)
        reg.loadFromContent(content)
        return true
      except CatchableError:
        return false
    return false

proc findPackage*(reg: PackageRegistry, name: string): Option[RegistryPackage] =
  let key = name.toLowerAscii()
  if reg.packages.hasKey(key):
    return some(reg.packages[key])
  return none(RegistryPackage)
