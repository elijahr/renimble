import std/[os, osproc]

type SolverResult* = object
  success*: bool
  commandRan*: string
  output*: string
  usedNativeSolver*: bool

proc isCommandAvailable*(cmd: string): bool =
  let testCmd =
    if defined(windows):
      "where " & cmd
    else:
      "which " & cmd
  let (_, exitCode) = execCmdEx(testCmd)
  return exitCode == 0

proc runNativeLockfileSync*(
    workingDir: string = ".", packageNames: seq[string] = @[], isAtlas: bool = false
): SolverResult =
  ## Invokes the official ecosystem solver (nimble lock or atlas pin) to re-resolve
  ## and guarantee zero transitive dependency corruption in lockfiles.
  if isAtlas:
    if isCommandAvailable("atlas"):
      let cmd = "atlas pin"
      let (outp, exitCode) = execCmdEx(cmd, workingDir = workingDir)
      return SolverResult(
        success: exitCode == 0, commandRan: cmd, output: outp, usedNativeSolver: true
      )
    else:
      return SolverResult(
        success: false,
        commandRan: "atlas",
        output: "atlas CLI not found in PATH",
        usedNativeSolver: false,
      )
  else:
    if isCommandAvailable("nimble"):
      # Run targeted nimble lock if package names given
      var cmd = "nimble lock"
      if packageNames.len > 0:
        for p in packageNames:
          cmd.add(" " & quoteShell(p))
      let (outp, exitCode) = execCmdEx(cmd, workingDir = workingDir)
      if exitCode == 0:
        return SolverResult(
          success: true, commandRan: cmd, output: outp, usedNativeSolver: true
        )
      else:
        # Fallback to general nimble lock without specific arguments
        let fallbackCmd = "nimble lock"
        let (fbOutp, fbCode) = execCmdEx(fallbackCmd, workingDir = workingDir)
        return SolverResult(
          success: fbCode == 0,
          commandRan: fallbackCmd,
          output: if fbCode == 0: fbOutp else: outp,
          usedNativeSolver: true,
        )
    else:
      return SolverResult(
        success: false,
        commandRan: "nimble",
        output: "nimble CLI not found in PATH",
        usedNativeSolver: false,
      )
