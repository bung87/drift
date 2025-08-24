## Git client abstraction for version control operations in Drift editor
## Provides clean interface for Git operations without direct command dependencies

import std/[osproc, strutils, sequtils, tables, os, streams]
import chronos except Result
import results
import ../../shared/[types, constants, errors, utils]

# Git file status enumeration
type GitFileStatus* = enum
  gfsUnmodified = "unmodified"
  gfsModified = "modified"
  gfsAdded = "added"
  gfsDeleted = "deleted"
  gfsRenamed = "renamed"
  gfsCopied = "copied"
  gfsUnmerged = "unmerged"
  gfsUntracked = "untracked"
  gfsIgnored = "ignored"

# Git repository state
type GitRepoState* = enum
  grsNormal = "normal"
  grsMerging = "merging"
  grsRebasing = "rebasing"
  grsCherryPicking = "cherry_picking"
  grsReverting = "reverting"
  grsBisecting = "bisecting"

# Git branch information
type GitBranch* = object
  name*: string
  isActive*: bool
  isRemote*: bool
  upstream*: string
  ahead*: int
  behind*: int
  lastCommit*: string
  lastCommitTime*: float

# Git commit information
type GitCommit* = object
  hash*: string
  shortHash*: string
  author*: string
  email*: string
  message*: string
  timestamp*: float
  parents*: seq[string]

# Git file change information
type GitFileChange* = object
  path*: string
  status*: GitFileStatus
  stagedStatus*: GitFileStatus
  workingStatus*: GitFileStatus
  oldPath*: string # For renames/copies
  similarity*: int # Percentage for renames/copies

# Git repository information
type GitRepository* = object
  path*: string
  workingDirectory*: string
  gitDirectory*: string
  currentBranch*: string
  state*: GitRepoState
  hasChanges*: bool
  hasStaged*: bool
  isDetached*: bool
  remotes*: seq[string]

# Git command configuration
type GitCommandConfig* = object
  timeout*: float
  retries*: int
  workingDirectory*: string
  environment*: Table[string, string]

# Git command result
type GitCommandResult* = object
  exitCode*: int
  stdout*: string
  stderr*: string
  command*: string
  duration*: float

# Git client implementation
type GitClient* = ref object
  gitExecutable*: string
  defaultConfig*: GitCommandConfig
  repositoryCache*: Table[string, GitRepository]
  cacheTimeout*: float
  isAvailable*: bool
  version*: string
  globalConfig*: Table[string, string]

# Constructor
proc newGitClient*(gitExecutable: string = "git"): GitClient =
  result = GitClient(
    gitExecutable: gitExecutable,
    defaultConfig: GitCommandConfig(
      timeout: GIT_COMMAND_TIMEOUT,
      retries: 1,
      workingDirectory: "",
      environment: initTable[string, string]()
    ),
    repositoryCache: initTable[string, GitRepository](),
    cacheTimeout: GIT_STATUS_UPDATE_INTERVAL,
    isAvailable: false,
    version: "",
    globalConfig: initTable[string, string]()
  )

# Low-level command execution
proc executeCommand*(
  client: GitClient,
  args: seq[string],
  config: GitCommandConfig = GitCommandConfig()
): Future[Result[GitCommandResult, GitError]] {.async.} =
  ## Execute git command with arguments
  if not client.isAvailable:
    result = err(newGitError(
      ERROR_GIT_NOT_INSTALLED,
      "Git is not available",
      args.join(" "),
      ""
    ))
    return

  let effectiveConfig = if config.timeout > 0: config else: client.defaultConfig
  let workingDir = if effectiveConfig.workingDirectory.len > 0:
    effectiveConfig.workingDirectory
  else:
    getCurrentDir()

  # let fullCommand = @[client.gitExecutable] & args  # Unused variable
  let startTime = getCurrentTimestamp()

  try:
    let process = startProcess(
      client.gitExecutable,
      args = args,
      workingDir = workingDir,
      options = {poUsePath, poStdErrToStdOut}
    )

    let output = streams.readAll(process.outputStream)
    let exitCode = process.waitForExit()
    let duration = getCurrentTimestamp() - startTime

    if exitCode == 0:
      return ok(GitCommandResult(
        exitCode: exitCode,
        stdout: output,
        stderr: "",
        command: args.join(" "),
        duration: duration
      ))
    else:
      return err(newGitError(
        ERROR_GIT_COMMAND_FAILED,
        "Git command failed: " & output,
        args.join(" "),
        workingDir
      ))

  except OSError as e:
    return err(newGitError(
      ERROR_GIT_COMMAND_FAILED,
      "Failed to execute git command: " & e.msg,
      args.join(" "),
      workingDir
    ))

# Git availability and initialization
proc checkGitAvailability*(client: GitClient): Future[Result[void, GitError]] {.async.} =
  ## Check if Git is available and get version
  try:
    # Run git --version directly, not via executeCommand (which checks isAvailable)
    let process = startProcess(client.gitExecutable, args = @["--version"], options = {poUsePath, poStdErrToStdOut})
    let output = streams.readAll(process.outputStream)
    let exitCode = process.waitForExit()
    if exitCode != 0:
      result = err(newGitError(
        ERROR_GIT_NOT_INSTALLED,
        "Git not found or not executable",
        "--version",
        ""
      ))
      return
    let versionOutput = output.strip()
    if versionOutput.startsWith("git version"):
      client.version = versionOutput.split(" ")[2]
      client.isAvailable = true
      result = ok()
    else:
      result = err(newGitError(
        ERROR_GIT_NOT_INSTALLED,
        "Invalid git version output: " & versionOutput,
        "--version",
        ""
      ))
      return
  except:
    result = err(newGitError(
      ERROR_GIT_NOT_INSTALLED,
      "Failed to check git availability",
      "--version",
      ""
    ))

proc loadGlobalConfig*(client: GitClient): Future[Result[void, GitError]] {.async.} =
  ## Load global Git configuration
  if not client.isAvailable:
    result = err(newGitError(ERROR_GIT_NOT_INSTALLED, "Git is not available", "config --global --list", ""))
    return
  let cmdResult = await client.executeCommand(@["config", "--global", "--list"])
  if cmdResult.isErr:
    return err(cmdResult.error)

  let output = cmdResult.get().stdout
  for line in output.split('\n'):
    if '=' in line:
      let parts = line.split('=', 1)
      if parts.len == 2:
        client.globalConfig[parts[0]] = parts[1]

  result = ok()

# Repository detection and management
proc findGitRepository*(client: GitClient, path: string): Result[GitRepository, GitError] =
  ## Find Git repository starting from given path
  var currentPath = path.normalizePath()

  while currentPath.len > 0:
    let gitDir = currentPath / ".git"
    if dirExists(gitDir) or fileExists(gitDir):
      # Found .git directory or file (for worktrees)
      let repo = GitRepository(
        path: currentPath,
        workingDirectory: currentPath,
        gitDirectory: gitDir,
        currentBranch: "",
        state: grsNormal,
        hasChanges: false,
        hasStaged: false,
        isDetached: false,
        remotes: @[]
      )
      return ok(repo)

    let parentPath = currentPath.parentDir()
    if parentPath == currentPath:
      break # Reached root
    currentPath = parentPath

  return err(gitNotRepository(path))

proc isGitRepository*(client: GitClient, path: string): bool =
  ## Check if path is within a Git repository
  client.findGitRepository(path).isOk

proc initRepository*(client: GitClient, path: string): Future[Result[GitRepository, GitError]] {.async.} =
  ## Initialize new Git repository
  let cmdResult = await client.executeCommand(@["init"], GitCommandConfig(workingDirectory: path))
  if cmdResult.isErr:
    return err(cmdResult.error)

  return client.findGitRepository(path)

# Repository state
proc getRepositoryState*(client: GitClient, path: string): Future[Result[GitRepoState, GitError]] {.async.} =
  ## Get current repository state (merging, rebasing, etc.)
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  let repo = repoResult.get()
  let gitDir = repo.gitDirectory

  # Check for various Git states
  if fileExists(gitDir / "MERGE_HEAD"):
    return ok(grsMerging)
  elif dirExists(gitDir / "rebase-merge") or dirExists(gitDir / "rebase-apply"):
    return ok(grsRebasing)
  elif fileExists(gitDir / "CHERRY_PICK_HEAD"):
    return ok(grsCherryPicking)
  elif fileExists(gitDir / "REVERT_HEAD"):
    return ok(grsReverting)
  elif fileExists(gitDir / "BISECT_LOG"):
    return ok(grsBisecting)
  else:
    return ok(grsNormal)



# Utility functions
proc parseGitStatusChar(c: char): GitFileStatus =
  ## Parse single character Git status
  case c:
  of ' ': gfsUnmodified
  of 'M': gfsModified
  of 'A': gfsAdded
  of 'D': gfsDeleted
  of 'R': gfsRenamed
  of 'C': gfsCopied
  of 'U': gfsUnmerged
  of '?': gfsUntracked
  of '!': gfsIgnored
  else: gfsUnmodified

proc parseGitStatus(workingChar: char, stagedChar: char): GitFileStatus =
  ## Parse Git status from working and staged characters
  if workingChar != ' ':
    return parseGitStatusChar(workingChar)
  elif stagedChar != ' ':
    return parseGitStatusChar(stagedChar)
  else:
    return gfsUnmodified

# File status operations
proc getStatus*(client: GitClient, path: string): Future[Result[seq[GitFileChange], GitError]] {.async.} =
  ## Get Git status for all files in repository
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["status", "--porcelain=v1", "-z"], config)
  if cmdResult.isErr:
    return err(cmdResult.error)

  var changes: seq[GitFileChange] = @[]
  let output = cmdResult.get().stdout

  # Parse porcelain output
  var i = 0
  while i < output.len:
    if i + 2 >= output.len:
      break

    let stagedChar = output[i]
    let workingChar = output[i + 1]
    i += 3 # Skip status chars and space

    # Read filename (until null terminator)
    var filename = ""
    while i < output.len and output[i] != '\0':
      filename.add(output[i])
      i += 1
    i += 1 # Skip null terminator

    if filename.len > 0:
      let change = GitFileChange(
        path: filename,
        status: parseGitStatus(workingChar, stagedChar),
        stagedStatus: parseGitStatusChar(stagedChar),
        workingStatus: parseGitStatusChar(workingChar),
        oldPath: "",
        similarity: 0
      )
      changes.add(change)

  return ok(changes)

# Repository information
proc getRepositoryInfo*(client: GitClient, path: string): Future[Result[GitRepository, GitError]] {.async.} =
  ## Get comprehensive repository information
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  var repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  # Get current branch
  let branchResult = await client.executeCommand(@["rev-parse", "--abbrev-ref", "HEAD"], config)
  if branchResult.isOk:
    repo.currentBranch = branchResult.get().stdout.strip()
    repo.isDetached = repo.currentBranch == "HEAD"

  # Get repository state
  let stateResult = await client.getRepositoryState(repo.workingDirectory)
  if stateResult.isOk:
    repo.state = stateResult.get()

  # Check for changes
  let statusResult = await client.getStatus(repo.workingDirectory)
  if statusResult.isOk:
    let changes = statusResult.get()
    repo.hasChanges = changes.len > 0
    repo.hasStaged = changes.anyIt(it.stagedStatus != gfsUnmodified)

  # Get remotes
  let remotesResult = await client.executeCommand(@["remote"], config)
  if remotesResult.isOk:
    repo.remotes = remotesResult.get().stdout.strip().split('\n').filterIt(it.len > 0)

  # Cache the result
  client.repositoryCache[repo.workingDirectory] = repo

  return ok(repo)

proc getFileStatus*(client: GitClient, filePath: string): Future[Result[GitFileChange, GitError]] {.async.} =
  ## Get Git status for specific file
  let allStatus = await client.getStatus(filePath.parentDir())
  if allStatus.isErr:
    return err(allStatus.error)

  let fileName = filePath.extractFilename()
  for change in allStatus.get():
    if change.path == fileName or change.path.endsWith("/" & fileName):
      return ok(change)

  # File not in Git status (unmodified)
  return ok(GitFileChange(
    path: filePath,
    status: gfsUnmodified,
    stagedStatus: gfsUnmodified,
    workingStatus: gfsUnmodified,
    oldPath: "",
    similarity: 0
  ))

# Staging operations
proc addFile*(client: GitClient, filePath: string): Future[Result[void, GitError]] {.async.} =
  ## Add file to staging area
  let repoResult = client.findGitRepository(filePath)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["add", filePath], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

proc addAll*(client: GitClient, path: string): Future[Result[void, GitError]] {.async.} =
  ## Add all changes to staging area
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["add", "."], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

proc resetFile*(client: GitClient, filePath: string): Future[Result[void, GitError]] {.async.} =
  ## Remove file from staging area
  let repoResult = client.findGitRepository(filePath)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["reset", "HEAD", filePath], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

# Commit operations
proc commit*(client: GitClient, path: string, message: string, amend: bool = false): Future[Result[string, GitError]] {.async.} =
  ## Create commit with message
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  var args = @["commit", "-m", message]
  if amend:
    args.add("--amend")

  let cmdResult = await client.executeCommand(args, config)
  if cmdResult.isOk:
    # Get the commit hash
    let hashResult = await client.executeCommand(@["rev-parse", "HEAD"], config)
    if hashResult.isOk:
      return ok(hashResult.get().stdout.strip())
    else:
      return ok("") # Commit succeeded but couldn't get hash
  else:
    return err(cmdResult.error)

# Branch operations
proc getBranches*(client: GitClient, path: string): Future[Result[seq[GitBranch], GitError]] {.async.} =
  ## Get list of all branches
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["branch", "-a", "-v"], config)
  if cmdResult.isErr:
    return err(cmdResult.error)

  var branches: seq[GitBranch] = @[]
  for line in cmdResult.get().stdout.split('\n'):
    if line.strip().len == 0:
      continue

    let isActive = line.startsWith("*")
    let cleanLine = line.replace("*", " ").strip()
    let parts = cleanLine.split()

    if parts.len >= 2:
      let name = parts[0]
      let lastCommit = parts[1]
      let isRemote = name.contains("/")

      branches.add(GitBranch(
        name: name,
        isActive: isActive,
        isRemote: isRemote,
        upstream: "",
        ahead: 0,
        behind: 0,
        lastCommit: lastCommit,
        lastCommitTime: 0.0
      ))

  return ok(branches)

proc getCurrentBranch*(client: GitClient, path: string): Future[Result[string, GitError]] {.async.} =
  ## Get name of current branch
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["rev-parse", "--abbrev-ref", "HEAD"], config)
  if cmdResult.isOk:
    return ok(cmdResult.get().stdout.strip())
  else:
    return err(cmdResult.error)

proc createBranch*(client: GitClient, path: string, branchName: string, checkout: bool = true): Future[Result[void, GitError]] {.async.} =
  ## Create new branch
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  var args: seq[string]
  if checkout:
    args = @["checkout", "-b", branchName]
  else:
    args = @["branch", branchName]
  let cmdResult = await client.executeCommand(args, config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

proc checkoutBranch*(client: GitClient, path: string, branchName: string): Future[Result[void, GitError]] {.async.} =
  ## Switch to existing branch
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["checkout", branchName], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

# Remote operations
proc getRemotes*(client: GitClient, path: string): Future[Result[seq[string], GitError]] {.async.} =
  ## Get list of remotes
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    return err(repoResult.error)

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["remote"], config)
  if cmdResult.isOk:
    return ok(cmdResult.get().stdout.strip().split('\n').filterIt(it.len > 0))
  else:
    return err(cmdResult.error)

proc fetch*(client: GitClient, path: string, remote: string = "origin"): Future[Result[void, GitError]] {.async.} =
  ## Fetch changes from remote
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["fetch", remote], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

proc pull*(client: GitClient, path: string, remote: string = "origin"): Future[Result[void, GitError]] {.async.} =
  ## Pull changes from remote
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let cmdResult = await client.executeCommand(@["pull", remote], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

proc push*(client: GitClient, path: string, remote: string = "origin", branch: string = ""): Future[Result[void, GitError]] {.async.} =
  ## Push changes to remote
  let repoResult = client.findGitRepository(path)
  if repoResult.isErr:
    result = err(repoResult.error)
    return

  let repo = repoResult.get()
  let config = GitCommandConfig(workingDirectory: repo.workingDirectory)

  let targetBranch = if branch.len > 0: branch else: repo.currentBranch
  let cmdResult = await client.executeCommand(@["push", remote, targetBranch], config)
  if cmdResult.isOk:
    result = ok()
  else:
    result = err(cmdResult.error)

# Configuration
proc setDefaultTimeout*(client: GitClient, timeout: float) =
  client.defaultConfig.timeout = timeout

proc setDefaultWorkingDirectory*(client: GitClient, directory: string) =
  client.defaultConfig.workingDirectory = directory

# Cache management
proc clearCache*(client: GitClient) =
  client.repositoryCache.clear()

proc setCacheTimeout*(client: GitClient, timeout: float) =
  client.cacheTimeout = timeout

# Cleanup
proc cleanup*(client: GitClient) =
  client.repositoryCache.clear()
  client.globalConfig.clear()
