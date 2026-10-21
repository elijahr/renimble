import std/[json, tables, strutils]
import types

proc parseLockFile*(content: string, filePath: string = ""): LockFile =
  result.filePath = filePath
  result.version = 1
  result.packages = initTable[string, LockPackage]()

  if content.strip().len == 0:
    return

  let node = parseJson(content)
  if node.hasKey("version"):
    result.version = node["version"].getInt()

  if node.hasKey("packages") and node["packages"].kind == JObject:
    for pkgName, pkgNode in node["packages"]:
      var pkg = LockPackage()
      if pkgNode.hasKey("version"):
        pkg.version = pkgNode["version"].getStr()
      if pkgNode.hasKey("vcsRevision"):
        pkg.vcsRevision = pkgNode["vcsRevision"].getStr()
      if pkgNode.hasKey("url"):
        pkg.url = pkgNode["url"].getStr()
      if pkgNode.hasKey("downloadMethod"):
        pkg.downloadMethod = pkgNode["downloadMethod"].getStr()

      result.packages[pkgName] = pkg

proc serializeLockFile*(lock: LockFile): string =
  var root = newJObject()
  root["version"] = newJInt(lock.version)

  var pkgs = newJObject()
  for name, pkg in lock.packages:
    var pNode = newJObject()
    pNode["version"] = newJString(pkg.version)
    pNode["vcsRevision"] = newJString(pkg.vcsRevision)
    pNode["url"] = newJString(pkg.url)
    pNode["downloadMethod"] = newJString(if pkg.downloadMethod.len > 0: pkg.downloadMethod else: "git")
    pkgs[name] = pNode

  root["packages"] = pkgs
  result = pretty(root, 2) & "\n"

proc updateLockPackage*(lock: var LockFile, pkgName: string, newVersion: string, newSha: string) =
  if lock.packages.hasKey(pkgName):
    var pkg = lock.packages[pkgName]
    pkg.version = newVersion
    if newSha.len > 0:
      pkg.vcsRevision = newSha
    lock.packages[pkgName] = pkg
  else:
    lock.packages[pkgName] = LockPackage(
      version: newVersion,
      vcsRevision: newSha,
      downloadMethod: "git"
    )
