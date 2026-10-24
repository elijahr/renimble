import std/[json, tables, strutils, sets, algorithm]
import types, declarative_parser

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
      if pkgNode.hasKey("dependencies") and pkgNode["dependencies"].kind == JArray:
        for depNode in pkgNode["dependencies"]:
          pkg.dependencies.add(depNode.getStr())

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
    if pkg.dependencies.len > 0:
      var depsArr = newJArray()
      for dep in pkg.dependencies:
        depsArr.add(newJString(dep))
      pNode["dependencies"] = depsArr
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
      downloadMethod: "git",
      dependencies: @[]
    )

proc findDanglingDependencies*(manifest: NimbleManifest, lock: LockFile): seq[string] =
  ## Returns package names required by the manifest that are not present in the lockfile.
  result = @[]
  for dep in manifest.dependencies:
    if dep.name.toLowerAscii() == "nim":
      continue
    let clean = cleanPackageName(dep.name)
    if not lock.packages.hasKey(dep.name) and not lock.packages.hasKey(clean):
      result.add(dep.name)

proc detectCircularDependencies*(depGraph: Table[string, seq[string]]): seq[seq[string]] =
  ## Identifies circular dependency cycles in a directed package dependency graph.
  ## Returns each cycle as a sequence of package names, e.g., @["A", "B", "A"].
  var cycles: seq[seq[string]] = @[]
  var visited = initHashSet[string]()
  var inStack = initHashSet[string]()
  var stack: seq[string] = @[]
  var seenCycleKeys = initHashSet[string]()

  proc dfs(u: string, outCycles: var seq[seq[string]]) =
    visited.incl(u)
    inStack.incl(u)
    stack.add(u)

    if depGraph.hasKey(u):
      for v in depGraph[u]:
        if v in inStack:
          # Cycle found from v to u back to v
          let idx = stack.find(v)
          if idx != -1:
            let cycle = stack[idx..^1] & @[v]
            # Normalize cycle key for deduplication
            let cycleKey = cycle.join("->")
            if cycleKey notin seenCycleKeys:
              seenCycleKeys.incl(cycleKey)
              outCycles.add(cycle)
        elif v notin visited:
          dfs(v, outCycles)

    discard stack.pop()
    inStack.excl(u)

  var sortedNodes: seq[string] = @[]
  for k in depGraph.keys:
    sortedNodes.add(k)
  sortedNodes.sort()

  for node in sortedNodes:
    if node notin visited:
      dfs(node, cycles)

  result = cycles

proc validateLockIntegrity*(manifest: NimbleManifest, lock: LockFile): seq[string] =
  ## Performs comprehensive verification of lockfile integrity against the manifest,
  ## detecting dangling dependencies, malformed package entries, and dependency cycles.
  result = @[]

  # 1. Manifest-to-lockfile dangling dependencies
  let dangling = findDanglingDependencies(manifest, lock)
  for dep in dangling:
    result.add("Dangling dependency: manifest requires '" & dep & "', but it is missing from lockfile")

  # 2. Package entry completeness & transitive dangling references
  var sortedPkgNames: seq[string] = @[]
  for k in lock.packages.keys:
    sortedPkgNames.add(k)
  sortedPkgNames.sort()

  for name in sortedPkgNames:
    let pkg = lock.packages[name]
    if pkg.version.len == 0:
      result.add("Malformed lockfile entry: package '" & name & "' has empty version")
    if pkg.vcsRevision.len == 0:
      result.add("Malformed lockfile entry: package '" & name & "' has empty vcsRevision")
    if pkg.url.len == 0:
      result.add("Malformed lockfile entry: package '" & name & "' has empty url")
    for transDep in pkg.dependencies:
      if transDep.toLowerAscii() != "nim" and not lock.packages.hasKey(transDep):
        result.add("Dangling transitive dependency: package '" & name & "' requires '" & transDep & "', but it is missing from lockfile")

  # 3. Circular dependencies in lockfile dependency graph
  var graph = initTable[string, seq[string]]()
  for name, pkg in lock.packages:
    graph[name] = pkg.dependencies
  let cycles = detectCircularDependencies(graph)
  for c in cycles:
    result.add("Circular dependency detected: " & c.join(" -> "))

