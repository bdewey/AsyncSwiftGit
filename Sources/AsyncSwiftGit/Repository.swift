// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation
import Logging

extension git_merge_analysis_t: OptionSet {}
extension git_merge_preference_t: OptionSet {}

private extension Logger {
  static let repository: Logger = {
    var logger = Logger(label: "org.brians-brain.AsyncSwiftGit.Repository")
    logger.logLevel = .debug
    logger[metadataKey: "subsystem"] = "repository"
    return logger
  }()
}

public protocol GitConflictResolver {
  /// Resolve a conflict in the repository.
  ///
  /// Resolving a conflict requires, at minimum, removing the conflict entries from `index`. For example, ``Index/removeConflictEntries(for:)`` will remove
  /// any conflicting entries.
  ///
  /// If the repository has a working directory, then there will be a _conflict file_ in the working directory that also needs to be cleaned up. Some strategies:
  ///
  /// - Explicitly write the resolved contents to that file in the working directory
  /// - Return `requiresCheckout`, which will tell ``Repository/merge(revspec:resolver:signature:)`` to update the working directory to match the contents of the Index. This is the strategy to use if you fixed the Index by just picking the `ours` or `theirs` conflicting entry.
  ///
  /// - Parameters:
  ///   - conflict: The conflicting index entries.
  ///   - index: The repository index.
  ///   - repository: The repository.
  /// - Returns: A tuple indicating if the conflict was resolved, and if so, whether we need to check out the Index to update the working directory.
  func resolveConflict(_ conflict: Index.ConflictEntry, index: Index, repository: Repository) throws -> (resolved: Bool, requiresCheckout: Bool)
}

/// A value that represents progress towards a goal.
public enum Progress<ProgressType, ResultType> {
  /// Progress towards the goal, storing the progress value.
  case progress(ProgressType)

  /// The goal is completed, storing the resulting goal value.
  case completed(ResultType)
}

/// Representation of a git repository, including all its object contents.
///
/// - note: This class is not thread-safe. Do not use it from more than one thread at the same time.
public final class Repository {
  typealias FetchProgressBlock = (FetchProgress) -> Void
  typealias CloneProgressBlock = (Result<Double, Error>) -> Void

  /// The Clibgit2 repository pointer managed by this actor.
  private let repositoryPointer: OpaquePointer

  /// If true, this class is the owner of `repositoryPointer` and should free it on deinit.
  private let isOwner: Bool

  /// The working directory of the repository, or `nil` if this is a bare repository.
  public nonisolated let workingDirectoryURL: URL?

  /// Creates a Git repository at a location.
  /// - Parameters:
  ///   - url: The location to create a Git repository at.
  ///   - bare: Whether the repository should be "bare". A bare repository does not have a corresponding working directory.
  public convenience init(createAt url: URL, bare: Bool = false) throws {
    let repositoryPointer = try GitError.checkAndReturn(apiName: "git_repository_init") { pointer in
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        "main".withCString { branchNamePointer in
          var options = git_repository_init_options()
          git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION))
          options.initial_head = branchNamePointer
          if bare {
            options.flags = GIT_REPOSITORY_INIT_BARE.rawValue
          }
          options.flags |= GIT_REPOSITORY_INIT_MKDIR.rawValue
          return git_repository_init_ext(&pointer, fileSystemPath, &options)
        }
      }
    }
    self.init(repositoryPointer: repositoryPointer, isOwner: true)
  }

  /// Opens a git repository at a specified location.
  /// - Parameter url: The location of the repository to open.
  public convenience init(openAt url: URL) throws {
    let repositoryPointer = try GitError.checkAndReturn(apiName: "git_repository_open") { pointer in
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        git_repository_open(&pointer, fileSystemPath)
      }
    }
    self.init(repositoryPointer: repositoryPointer, isOwner: true)
  }

  init(repositoryPointer: OpaquePointer, isOwner: Bool) {
    self.repositoryPointer = repositoryPointer
    self.isOwner = isOwner
    if let pathPointer = git_repository_workdir(repositoryPointer), let path = String(validatingUTF8: pathPointer) {
      self.workingDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)
    } else {
      self.workingDirectoryURL = nil
    }
  }

  deinit {
    if isOwner {
      git_repository_free(repositoryPointer)
    }
  }

  /// Clones a repository.
  /// - Parameters:
  ///   - remoteURL: The URL to the repository to clone.
  ///   - localURL: The URL of the local destination for the repository.
  ///   - credentials: Credentials to use to connect to `remoteURL`
  /// - Returns: A ``Repository`` representing the new local copy.
  public static func clone(
    from remoteURL: URL,
    to localURL: URL,
    credentials: Credentials = .default
  ) async throws -> Repository {
    var repository: Repository?
    for try await progress in cloneProgress(from: remoteURL, to: localURL, credentials: credentials) {
      switch progress {
      case .completed(let repo):
        repository = repo
      case .progress:
        break
      }
    }
    return repository!
  }

  /// Clones a repository, reporting progress.
  /// - returns: An `AsyncThrowingStream` that returns intermediate ``FetchProgress`` while fetching and the final ``Repository`` upon completion.
  public static func cloneProgress(
    from remoteURL: URL,
    to localURL: URL,
    credentials: Credentials = .default
  ) -> AsyncThrowingStream<Progress<FetchProgress, Repository>, Error> {
    AsyncThrowingStream<Progress<FetchProgress, Repository>, Error> { continuation in
      let progressCallback: FetchProgressBlock = { progress in
        continuation.yield(.progress(progress))
      }
      let cloneOptions = CloneOptions(
        fetchOptions: FetchOptions(credentials: credentials, progressCallback: progressCallback)
      )
      do {
        let repositoryPointer = try cloneOptions.withOptions { options -> OpaquePointer in
          var options = options
          return try GitError.checkAndReturn(apiName: "git_clone", closure: { pointer in
            localURL.withUnsafeFileSystemRepresentation { filePath in
              git_clone(&pointer, remoteURL.absoluteString, filePath, &options)
            }
          })
        }
        continuation.yield(.completed(Repository(repositoryPointer: repositoryPointer, isOwner: true)))
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  // MARK: - Remotes

  /// Adds a named remote to the repo.
  /// - Parameters:
  ///   - name: The name of the remote. (E.g., `origin`)
  ///   - url: The URL for the remote.
  public func addRemote(_ name: String, url: URL) throws {
    let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_create", closure: { pointer in
      git_remote_create(&pointer, repositoryPointer, name, url.absoluteString)
    })
    git_remote_free(remotePointer)
  }

  /// Deletes the named remote from the repository.
  public func deleteRemote(_ name: String) throws {
    try GitError.check(apiName: "git_remote_delete", closure: {
      git_remote_delete(repositoryPointer, name)
    })
  }

  /// Returns the URL associated with a particular git remote name.
  /// - Parameter remoteName: The name of the remote. (For example, `origin`)
  /// - Returns: If `remoteName` exists, the URL corresponding to the remote. Returns `nil` if `remoteName` does not exist.
  /// - throws: ``GitError`` on any other error.
  public func remoteURL(for remoteName: String) throws -> URL? {
    do {
      let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_lookup", closure: { pointer in
        git_remote_lookup(&pointer, repositoryPointer, remoteName)
      })
      defer {
        git_remote_free(remotePointer)
      }
      if let remoteString = git_remote_url(remotePointer) {
        return URL(string: String(cString: remoteString))
      } else {
        return nil
      }
    } catch let gitError as GitError {
      if gitError.errorCode == GIT_ENOTFOUND.rawValue {
        return nil
      } else {
        throw gitError
      }
    }
  }

  // MARK: - Branches

  /// Creates a branch targeting a specific commit.
  /// - Parameters:
  ///   - name: The name of the branch to create.
  ///   - commitOID: The ``ObjectID`` of the commit to target.
  ///   - force: If true, force create the branch. If false, this operation will fail if a branch named `name` already exists.
  public func createBranch(named name: String, commitOID: ObjectID, force: Bool = false) throws {
    var oid = commitOID.oid
    let commitPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { pointer in
      git_commit_lookup(&pointer, repositoryPointer, &oid)
    })
    defer {
      git_object_free(commitPointer)
    }
    let branchPointer = try GitError.checkAndReturn(apiName: "git_branch_create", closure: { pointer in
      git_branch_create(&pointer, repositoryPointer, name, commitPointer, force ? 1 : 0)
    })
    git_reference_free(branchPointer)
  }

  /// Creates a branch targeting a named reference.
  /// - Parameters:
  ///   - name: The name of the branch to create.
  ///   - target: The name of the reference to target.
  ///   - force: If true, force create the branch. If false, this operation will fail if a branch named `name` already exists.
  ///   - setTargetAsUpstream: If true, set `target` as the upstream branch of the newly created branch.
  public func createBranch(named name: String, target: String, force: Bool = false, setTargetAsUpstream: Bool = false) throws {
    let referencePointer = try GitError.checkAndReturn(apiName: "git_reference_dwim", closure: { pointer in
      git_reference_dwim(&pointer, repositoryPointer, target)
    })
    defer {
      git_reference_free(referencePointer)
    }
    let commitPointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
      git_reference_peel(&pointer, referencePointer, GIT_OBJECT_COMMIT)
    })
    defer {
      git_object_free(commitPointer)
    }
    let branchPointer = try GitError.checkAndReturn(apiName: "git_branch_create", closure: { pointer in
      git_branch_create(&pointer, repositoryPointer, name, commitPointer, force ? 1 : 0)
    })
    defer {
      git_reference_free(branchPointer)
    }
    if setTargetAsUpstream {
      try GitError.check(apiName: "git_branch_set_upstream", closure: {
        git_branch_set_upstream(branchPointer, target)
      })
    }
  }

  @discardableResult
  /// Deletes the branch named `name`.
  ///
  /// - note: Unlike the `git branch --delete` command, this method does not check to see if the branch has been merged before deleting; it just deletes.
  ///
  /// - Parameter name: The name of the branch to delete.
  /// - returns The ``ObjectID`` of the commit that the branch pointed to, or nil if no branch named `name` was found.
  /// - throws ``GitError`` on any other error.
  public func deleteBranch(named name: String) throws -> ObjectID? {
    do {
      let branchPointer = try GitError.checkAndReturn(apiName: "git_branch_lookup", closure: { pointer in
        git_branch_lookup(&pointer, repositoryPointer, name, BranchType.all.gitType)
      })
      defer {
        git_reference_free(branchPointer)
      }
      let commitPointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
        git_reference_peel(&pointer, branchPointer, GIT_OBJECT_COMMIT)
      })
      defer {
        git_object_free(commitPointer)
      }
      let oid = git_commit_id(commitPointer)
      try GitError.check(apiName: "git_branch_delete", closure: {
        git_branch_delete(branchPointer)
      })
      return ObjectID(oid)
    } catch let error as GitError {
      if error.errorCode == GIT_ENOTFOUND.rawValue {
        return nil
      } else {
        throw error
      }
    }
  }

  /// Gets all branch names of a specific branch type.
  /// - Parameter type: The type of branch to query for.
  /// - Returns: The current branch names in the repository.
  public func branches(type: BranchType) throws -> [String] {
    let branchIterator = try GitError.checkAndReturn(apiName: "git_branch_iterator_new", closure: { pointer in
      git_branch_iterator_new(&pointer, repositoryPointer, type.gitType)
    })
    defer {
      git_branch_iterator_free(branchIterator)
    }
    var referencePointer: OpaquePointer?
    var type = GIT_BRANCH_ALL
    var result = git_branch_next(&referencePointer, &type, branchIterator)
    var branches: [String] = []
    while result == GIT_OK.rawValue {
      let branchName = String(cString: git_reference_name(referencePointer))
      branches.append(branchName)
      result = git_branch_next(&referencePointer, &type, branchIterator)
    }
    if result == GIT_ITEROVER.rawValue {
      return branches
    } else {
      throw GitError(errorCode: result, apiName: "git_branch_next")
    }
  }

  /// Returns the remote name for a remote tracking branch.
  /// - Parameter branchName: The full branch name
  /// - Returns: The remote name
  public func remoteName(branchName: String) throws -> String {
    var buffer = git_buf()
    try GitError.check(apiName: "git_branch_remote_name", closure: {
      git_branch_remote_name(&buffer, repositoryPointer, branchName)
    })
    return String(cString: buffer.ptr)
  }

  /// Tests if a branch exists in the repository.
  /// - Parameter name: The name of the branch.
  /// - Returns: True if the branch exists, false otherwise.
  public func branchExists(named name: String) throws -> Bool {
    do {
      let branchPointer = try GitError.checkAndReturn(apiName: "git_branch_lookup", closure: { pointer in
        git_branch_lookup(&pointer, repositoryPointer, name, GIT_BRANCH_LOCAL)
      })
      git_reference_free(branchPointer)
      return true
    } catch let error as GitError {
      if error.errorCode == GIT_ENOTFOUND.rawValue {
        return false
      } else {
        throw error
      }
    }
  }

  /// Get the upstream name of a branch.
  ///
  /// Given a local branch, this will return its remote-tracking branch information, as a full reference name, ie. “feature/nice” would become “refs/remote/origin/feature/nice”, depending on that branch’s configuration.
  /// - Parameter branchName: The name of the branch to query.
  /// - Returns: The upstream name of the branch, if it exists.
  /// - throws ``GitError`` if there is no upstream branch.
  public func upstreamName(of branchName: String) throws -> String {
    var buffer = git_buf()
    try GitError.check(apiName: "git_branch_upstream_name", closure: {
      git_branch_upstream_name(&buffer, repositoryPointer, branchName)
    })
    defer {
      git_buf_dispose(&buffer)
    }
    return String(cString: buffer.ptr)
  }

  // MARK: - References

  /// Lookup a reference by name in a repository.
  ///
  /// - Parameter name: The name of the reference. This needs to be the _full name_ of the reference (e.g., `refs/heads/main` instead of `main`).
  /// - Returns: The corresponding ``Reference`` if it exists, or `nil` if a reference named `name` is not found in the repository.
  public func lookupReference(name: String) throws -> Reference? {
    do {
      let referencePointer = try GitError.checkAndReturn(apiName: "git_reference_lookup", closure: { pointer in
        git_reference_lookup(&pointer, repositoryPointer, name)
      })
      return Reference(pointer: referencePointer)
    } catch let error as GitError {
      if error.errorCode == GIT_ENOTFOUND.rawValue {
        return nil
      }
      throw error
    }
  }

  /// A stream that emits ``FetchProgress`` structs during a fetch and concludes with the name of the default branch of the remote when the fetch is complete.
  public typealias FetchProgressStream = AsyncThrowingStream<Progress<FetchProgress, String?>, Error>

  /// Fetch from a named remote.
  /// - Parameters:
  ///   - remote: The remote to fetch
  ///   - credentials: Credentials to use for the fetch.
  /// - returns: An AsyncThrowingStream that emits the fetch progress. The fetch is not done until this stream finishes yielding values.
  public func fetchProgress(
    remote: String,
    pruneOption: FetchPruneOption = .unspecified,
    credentials: Credentials = .default
  ) -> FetchProgressStream {
    let fetchOptions = FetchOptions(credentials: credentials, pruneOption: pruneOption, progressCallback: nil)
    let resultStream = FetchProgressStream { continuation in
      Task {
        fetchOptions.progressCallback = { progressResult in
          continuation.yield(.progress(progressResult))
        }
        do {
          let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_lookup", closure: { pointer in
            git_remote_lookup(&pointer, repositoryPointer, remote)
          })
          defer {
            git_remote_free(remotePointer)
          }
          if let remoteURL = git_remote_url(remotePointer) {
            let remoteURLString = String(cString: remoteURL)
            print("Fetching from \(remoteURLString)")
          }
          try GitError.check(apiName: "git_remote_fetch", closure: {
            fetchOptions.withOptions { options in
              git_remote_fetch(remotePointer, nil, &options, "fetch")
            }
          })
          do {
            var buffer = git_buf()
            try GitError.check(apiName: "git_remote_default_branch", closure: {
              git_remote_default_branch(&buffer, remotePointer)
            })
            defer {
              git_buf_free(&buffer)
            }
            let defaultBranch = String(cString: buffer.ptr)
            continuation.yield(.completed(defaultBranch))
          } catch let error as GitError {
            if error.errorCode == GIT_ENOTFOUND.rawValue {
              continuation.yield(.completed(nil))
            } else {
              throw error
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
    return resultStream
  }

  @discardableResult
  /// Fetch from a named remote, waiting until the fetch is 100% complete before returning.
  /// - Parameters:
  ///   - remote: The remote to fetch
  ///   - credentials: Credentials to use for the fetch.
  /// - returns: The reference name for default branch for the remote.
  public func fetch(remote: String, credentials: Credentials = .default) async throws -> String? {
    var defaultBranch: String!
    for try await progress in fetchProgress(remote: remote, credentials: credentials) {
      switch progress {
      case .completed(let branch):
        defaultBranch = branch
      default:
        break
      }
    }
    return defaultBranch
  }

  /// Creates an `AsyncThrowingStream` that reports on the progress of checking out a reference.
  /// - Parameters:
  ///   - referenceShorthand: The reference to checkout. This can be a shorthand name (e.g., `main`) and git will resolve it using precedence rules to a full reference (`refs/heads/main`).
  ///   - checkoutStrategy: The checkout strategy.
  /// - Returns: An `AsyncThrowingStream` that emits ``CheckoutProgress`` structs reporting on the progress of checkout. Checkout is complete when the stream terminates.
  public func checkoutProgress(
    referenceShorthand: String,
    checkoutStrategy: git_checkout_strategy_t = GIT_CHECKOUT_SAFE
  ) -> AsyncThrowingStream<CheckoutProgress, Error> {
    AsyncThrowingStream { continuation in
      Task {
        do {
          try checkNormalState()
          let referencePointer = try GitError.checkAndReturn(apiName: "git_reference_dwim", closure: { pointer in
            git_reference_dwim(&pointer, repositoryPointer, referenceShorthand)
          })
          defer {
            git_reference_free(referencePointer)
          }
          let referenceName = String(cString: git_reference_name(referencePointer))
          print("Checking out \(referenceName)")
          let annotatedCommit = try GitError.checkAndReturn(apiName: "git_annotated_commit_from_ref", closure: { pointer in
            git_annotated_commit_from_ref(&pointer, repositoryPointer, referencePointer)
          })
          defer {
            git_annotated_commit_free(annotatedCommit)
          }
          let commitPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { pointer in
            git_commit_lookup(&pointer, repositoryPointer, git_annotated_commit_id(annotatedCommit))
          })
          defer {
            git_commit_free(commitPointer)
          }
          let checkoutOptions = CheckoutOptions(checkoutStrategy: checkoutStrategy) { progress in
            continuation.yield(progress)
          }
          try checkoutOptions.withOptions { options in
            try GitError.check(apiName: "git_checkout_tree", closure: {
              git_checkout_tree(repositoryPointer, commitPointer, &options)
            })
          }

          var targetRefname = git_reference_name(referencePointer)
          if git_reference_is_remote(referencePointer) != 0 {
            do {
              let branchPointer = try GitError.checkAndReturn(apiName: "git_branch_create_from_annotated", closure: { pointer in
                git_branch_create_from_annotated(&pointer, repositoryPointer, referenceName, annotatedCommit, 0)
              })
              defer {
                git_reference_free(branchPointer)
              }
              targetRefname = git_reference_name(branchPointer)
            } catch let error as GitError {
              guard error.errorCode == GIT_EEXISTS.rawValue else {
                throw error
              }
              let branchPointer = try GitError.checkAndReturn(apiName: "git_branch_create_from_annotated", closure: { pointer in
                git_branch_lookup(&pointer, repositoryPointer, referenceName, GIT_BRANCH_LOCAL)
              })
              defer {
                git_reference_free(branchPointer)
              }
              targetRefname = git_reference_name(branchPointer)
            }
          }
          try GitError.check(apiName: "git_repository_set_head", closure: {
            git_repository_set_head(repositoryPointer, targetRefname)
          })
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  public func checkout(
    revspec: String,
    checkoutStrategy: git_checkout_strategy_t = GIT_CHECKOUT_SAFE
  ) async throws {
    for try await _ in checkoutProgress(referenceShorthand: revspec, checkoutStrategy: checkoutStrategy) {}
  }

  /// The current set of ``StatusEntry`` structs that represent the current status of all items in the repository.
  public var statusEntries: [StatusEntry] {
    get throws {
      var options = git_status_options()
      git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION))
      let statusList = try GitError.checkAndReturn(apiName: "git_status_list_new", closure: { pointer in
        git_status_list_new(&pointer, repositoryPointer, &options)
      })
      defer {
        git_status_list_free(statusList)
      }
      let entryCount = git_status_list_entrycount(statusList)
      let entries = (0 ..< entryCount).compactMap { index -> StatusEntry? in
        let statusPointer = git_status_byindex(statusList, index)
        guard let status = statusPointer?.pointee else {
          return nil
        }
        return StatusEntry(status)
      }
      return entries
    }
  }

  /// Possible results from a merge operation.
  public enum MergeResult: Equatable {
    /// We fast-forwarded the current branch to a new commit.
    case fastForward(ObjectID)

    /// We created a merge commit in the current branch.
    case merge(ObjectID)

    /// No action was taken -- the current branch already has all changes from the target branch.
    case none

    public var isFastForward: Bool {
      switch self {
      case .fastForward: return true
      case .merge, .none: return false
      }
    }

    public var isMerge: Bool {
      switch self {
      case .merge: return true
      case .fastForward, .none: return false
      }
    }
  }

  /// Merge a `revspec` into the current branch.
  public func merge(
    revspec: String,
    resolver: GitConflictResolver? = nil,
    signature signatureBlock: @autoclosure () throws -> Signature
  ) throws -> MergeResult {
    try checkNormalState()

    let annotatedCommit = try GitError.checkAndReturn(apiName: "git_annotated_commit_from_revspec", closure: { pointer in
      git_annotated_commit_from_revspec(&pointer, repositoryPointer, revspec)
    })
    defer {
      git_annotated_commit_free(annotatedCommit)
    }

    var analysis = GIT_MERGE_ANALYSIS_NONE
    var mergePreference = GIT_MERGE_PREFERENCE_NONE
    var theirHeads: [OpaquePointer?] = [annotatedCommit]
    try GitError.check(apiName: "git_merge_analysis", closure: {
      git_merge_analysis(&analysis, &mergePreference, repositoryPointer, &theirHeads, theirHeads.count)
    })
    if analysis.contains(GIT_MERGE_ANALYSIS_FASTFORWARD), let oid = ObjectID(git_annotated_commit_id(annotatedCommit)) {
      // Fast forward
      try fastForward(to: oid, isUnborn: analysis.contains(GIT_MERGE_ANALYSIS_UNBORN))
      return .fastForward(oid)

    } else if analysis.contains(GIT_MERGE_ANALYSIS_NORMAL) {
      // Normal merge
      guard !mergePreference.contains(GIT_MERGE_PREFERENCE_FASTFORWARD_ONLY) else {
        throw GitError(
          errorCode: Int32(GIT_ERROR_INTERNAL.rawValue),
          apiName: "git_merge",
          customMessage: "Fast-forward is preferred, but only a merge is possible"
        )
      }
      let mergeOptions = MergeOptions(
        checkoutOptions: CheckoutOptions(checkoutStrategy: [GIT_CHECKOUT_FORCE, GIT_CHECKOUT_ALLOW_CONFLICTS]),
        mergeFlags: [],
        fileFlags: GIT_MERGE_FILE_STYLE_DIFF3
      )
      try mergeOptions.withOptions { merge_options, checkout_options in
        try GitError.check(apiName: "git_merge", closure: {
          git_merge(repositoryPointer, &theirHeads, theirHeads.count, &merge_options, &checkout_options)
        })
      }
      try checkForConflicts(resolver: resolver)
      let signature = try signatureBlock()
      let mergeCommitOID = try commitMerge(revspec: revspec, annotatedCommit: annotatedCommit, signature: signature)
      return .merge(mergeCommitOID)
    }

    return .none
  }

  /// Gets the `ObjectID` associated with `revspec`.
  /// - returns: `nil` if `revspec` doesn't exist
  /// - throws on other git errors.
  private func commitObjectID(revspec: String) throws -> ObjectID? {
    do {
      let commitPointer = try GitError.checkAndReturn(apiName: "git_revparse_single", closure: { pointer in
        git_revparse_single(&pointer, repositoryPointer, revspec)
      })
      defer {
        git_object_free(commitPointer)
      }
      // Assume our object is a commit
      return ObjectID(git_commit_id(commitPointer))
    } catch let error as GitError {
      if error.errorCode == GIT_ENOTFOUND.rawValue {
        return nil
      } else {
        throw error
      }
    }
  }

  public func countCommits(revspec: String) throws -> Int {
    var count = 0
    try enumerateCommits(revspec: revspec) { _ in
      count += 1
      return true
    }
    return count
  }

  public func commitsAheadBehind(other revspec: String) throws -> (ahead: Int, behind: Int) {
    let headObjectID = try commitObjectID(revspec: "HEAD")
    let otherObjectID = try commitObjectID(revspec: revspec)

    switch (headObjectID, otherObjectID) {
    case (.none, .none):
      return (ahead: 0, behind: 0)
    case (.some, .none):
      return (ahead: try countCommits(revspec: "HEAD"), behind: 0)
    case (.none, .some):
      return (ahead: 0, behind: try countCommits(revspec: revspec))
    case (.some(var headOID), .some(var otherOID)):
      var ahead = 0
      var behind = 0
      try GitError.check(apiName: "git_graph_ahead_behind", closure: {
        git_graph_ahead_behind(&ahead, &behind, repositoryPointer, &headOID.oid, &otherOID.oid)
      })
      return (ahead: ahead, behind: behind)
    }
  }

  public func commitsAheadBehind(sourceReference: Reference?, targetReference: Reference?) throws -> (ahead: Int, behind: Int) {
    let sourceObjectID = try sourceReference?.commit.objectID
    let targetObjectID = try targetReference?.commit.objectID

    switch (sourceObjectID, targetObjectID) {
    case (.none, .none):
      return (ahead: 0, behind: 0)
    case (.some, .none):
      let commits = try sourceReference?.name.flatMap { revspec in
        try countCommits(revspec: revspec)
      } ?? 0
      return (ahead: commits, behind: 0)
    case (.none, .some):
      let commits = try targetReference?.name.flatMap { revspec in
        try countCommits(revspec: revspec)
      } ?? 0
      return (ahead: 0, behind: commits)
    case (.some(var headOID), .some(var otherOID)):
      var ahead = 0
      var behind = 0
      try GitError.check(apiName: "git_graph_ahead_behind", closure: {
        git_graph_ahead_behind(&ahead, &behind, repositoryPointer, &headOID.oid, &otherOID.oid)
      })
      return (ahead: ahead, behind: behind)
    }
  }

  private func commitMerge(revspec: String, annotatedCommit: OpaquePointer, signature: Signature) throws -> ObjectID {
    let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
      git_repository_index(&pointer, repositoryPointer)
    })
    defer {
      git_index_free(indexPointer)
    }
    guard let headReference = try head else {
      // TODO: Support merging into an unborn branch
      throw GitError(errorCode: -9, apiName: "git_repository_head")
    }
    let headCommit = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
      git_reference_peel(&pointer, headReference.referencePointer, GIT_OBJECT_COMMIT)
    })
    defer {
      git_object_free(headCommit)
    }
    let annotatedCommitObjectPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { pointer in
      var oid = git_annotated_commit_id(annotatedCommit)!.pointee
      return git_commit_lookup(&pointer, repositoryPointer, &oid)
    })
    defer {
      git_object_free(annotatedCommitObjectPointer)
    }

    let treeOid = try GitError.checkAndReturnOID(apiName: "git_index_write_tree", closure: { pointer in
      git_index_write_tree(&pointer, indexPointer)
    })
    let treePointer = try GitError.checkAndReturn(apiName: "git_tree_lookup", closure: { pointer in
      var oid = treeOid.oid
      return git_tree_lookup(&pointer, repositoryPointer, &oid)
    })
    defer {
      git_tree_free(treePointer)
    }

    var parents: [OpaquePointer?] = [headCommit, annotatedCommitObjectPointer]
    let mergeCommitOID = try GitError.checkAndReturnOID(apiName: "git_commit_create", closure: { pointer in
      git_commit_create(
        &pointer,
        repositoryPointer,
        git_reference_name(headReference.referencePointer),
        signature.signaturePointer,
        signature.signaturePointer,
        nil,
        "Merge \(revspec)",
        treePointer,
        parents.count,
        &parents
      )
    })

    try cleanup()

    return mergeCommitOID
  }

  /// Throws an error if the repository is in a non-normal state (e.g., in the middle of a cherry pick or a merge)
  public func checkNormalState() throws {
    try GitError.check(apiName: "git_repository_state", closure: {
      git_repository_state(repositoryPointer)
    })
  }

  /// The current repository state.
  public var repositoryState: git_repository_state_t {
    let code = git_repository_state(repositoryPointer)
    return git_repository_state_t(UInt32(code))
  }

  /// Cleans up the repository if it's in a non-normal state.
  public func cleanup() throws {
    try GitError.check(apiName: "git_repository_state_cleanup", closure: {
      git_repository_state_cleanup(repositoryPointer)
    })
  }

  public enum ResetType {
    case soft
    case mixed
    case hard

    var reset_type: git_reset_t {
      switch self {
      case .soft:
        return GIT_RESET_SOFT
      case .mixed:
        return GIT_RESET_MIXED
      case .hard:
        return GIT_RESET_HARD
      }
    }
  }

  public func reset(revspec: String, type: ResetType) throws {
    let commitPointer = try GitError.checkAndReturn(apiName: "git_revparse_single", closure: { pointer in
      git_revparse_single(&pointer, repositoryPointer, revspec)
    })
    defer {
      git_object_free(commitPointer)
    }
    try GitError.check(apiName: "git_reset", closure: {
      git_reset(repositoryPointer, commitPointer, type.reset_type, nil)
    })
  }

  public func reset(commitOID: ObjectID, type: ResetType) throws {
    var oid = commitOID.oid
    let commitPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { pointer in
      git_commit_lookup(&pointer, repositoryPointer, &oid)
    })
    defer {
      git_object_free(commitPointer)
    }
    try GitError.check(apiName: "git_reset", closure: {
      git_reset(repositoryPointer, commitPointer, type.reset_type, nil)
    })
  }

  /// The index file for this repository.
  public var index: Index {
    get throws {
      let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
        git_repository_index(&pointer, repositoryPointer)
      })
      return Index(indexPointer)
    }
  }

  /// Throws ``ConflictError`` if there are conflicts in the current repository.
  public func checkForConflicts(resolver: GitConflictResolver?) throws {
    // See if there were conflicts
    let index = try index

    if !index.hasConflicts {
      // No conflicts
      return
    }

    // Try to resolve any conflicts
    var requiresCheckout = false
    for conflict in index.conflicts {
      if let result = try resolver?.resolveConflict(conflict, index: index, repository: self) {
        requiresCheckout = result.requiresCheckout || requiresCheckout
      }
    }

    // Make sure conflict resolution succeeded.

    let conflictingPaths = index.conflicts.map(\.path)
    if !conflictingPaths.isEmpty {
      throw ConflictError(conflictingPaths: conflictingPaths)
    }

    if requiresCheckout {
      // The resolver modified the index without modifying the working directory.
      // Do a checkout to make sure the working directory is up-to-date.
      let forceOptions = CheckoutOptions(checkoutStrategy: GIT_CHECKOUT_FORCE)
      try forceOptions.withOptions { options in
        try GitError.check(apiName: "git_checkout_index", closure: {
          git_checkout_index(repositoryPointer, index.indexPointer, &options)
        })
      }
    }
  }

  private func enumerateConflicts(
    in indexPointer: OpaquePointer,
    _ block: (_ ancestor: git_index_entry?, _ ours: git_index_entry?, _ theirs: git_index_entry?) throws -> Void
  ) throws {
    let iteratorPointer = try GitError.checkAndReturn(apiName: "git_index_conflict_iterator_new", closure: { pointer in
      git_index_conflict_iterator_new(&pointer, indexPointer)
    })
    defer {
      git_index_conflict_iterator_free(iteratorPointer)
    }

    var ancestor: UnsafePointer<git_index_entry>?
    var ours: UnsafePointer<git_index_entry>?
    var theirs: UnsafePointer<git_index_entry>?

    while git_index_conflict_next(&ancestor, &ours, &theirs, iteratorPointer) == 0 {
      try block(ancestor?.pointee, ours?.pointee, theirs?.pointee)
    }
  }

  private func fastForward(to objectID: ObjectID, isUnborn: Bool) throws {
    let headReference = isUnborn ? try createSymbolicReference(named: "HEAD", targeting: objectID) : try head!
    let targetPointer = try GitError.checkAndReturn(apiName: "git_object_lookup", closure: { pointer in
      var oid = objectID.oid
      return git_object_lookup(&pointer, repositoryPointer, &oid, GIT_OBJECT_COMMIT)
    })
    defer {
      git_object_free(targetPointer)
    }
    try GitError.check(apiName: "git_checkout_tree", closure: {
      let checkoutOptions = CheckoutOptions(checkoutStrategy: GIT_CHECKOUT_SAFE)
      return checkoutOptions.withOptions { options in
        git_checkout_tree(repositoryPointer, targetPointer, &options)
      }
    })
    let newTarget = try GitError.checkAndReturn(apiName: "git_reference_set_target", closure: { pointer in
      var oid = objectID.oid
      return git_reference_set_target(&pointer, headReference.referencePointer, &oid, nil)
    })
    git_reference_free(newTarget)
  }

  private func createSymbolicReference(named name: String, targeting objectID: ObjectID) throws -> Reference {
    let symbolicPointer = try GitError.checkAndReturn(apiName: "git_reference_lookup", closure: { pointer in
      git_reference_lookup(&pointer, repositoryPointer, name)
    })
    defer {
      git_reference_free(symbolicPointer)
    }
    let target = git_reference_symbolic_target(symbolicPointer)
    let targetReference = try GitError.checkAndReturn(apiName: "git_reference_create", closure: { pointer in
      var oid = objectID.oid
      return git_reference_create(&pointer, repositoryPointer, target, &oid, 0, nil)
    })
    return Reference(pointer: targetReference)
  }

  /// Returns the reference that HEAD points to, or `nil` if HEAD points to an unborn branch.
  public var head: Reference? {
    get throws {
      do {
        let reference = try GitError.checkAndReturn(apiName: "git_repository_head", closure: { pointer in
          git_repository_head(&pointer, repositoryPointer)
        })
        return Reference(pointer: reference)
      } catch let error as GitError {
        if error.errorCode == GIT_EUNBORNBRANCH.rawValue {
          return nil
        }
        throw error
      }
    }
  }

  public func setHead(referenceName: String) throws {
    try GitError.check(apiName: "git_repository_set_head", closure: {
      git_repository_set_head(repositoryPointer, referenceName)
    })
  }

  /// The ``ObjectID`` for the current value of HEAD.
  public var headObjectID: ObjectID? {
    get throws {
      try commitObjectID(revspec: "HEAD")
    }
  }

  /// Returns the `Tree` associated with the `HEAD` commit.
  public var headTree: Tree {
    get throws {
      let treePointer = try GitError.checkAndReturn(apiName: "git_revparse_single", closure: { pointer in
        git_revparse_single(&pointer, repositoryPointer, "HEAD^{tree}")
      })
      return Tree(treePointer)
    }
  }

  /// Returns a `Tree` associated with a specific `Entry`.
  public func lookupTree(for entry: TreeEntry) throws -> Tree {
    try lookupTree(for: entry.objectID)
  }

  public func lookupTree(for objectID: ObjectID) throws -> Tree {
    let treePointer = try GitError.checkAndReturn(apiName: "git_tree_lookup", closure: { pointer in
      var oid = objectID.oid
      return git_tree_lookup(&pointer, repositoryPointer, &oid)
    })
    return Tree(treePointer)
  }

  public func lookupTree(for refspec: String) throws -> Tree {
    let reference = try GitError.checkAndReturn(apiName: "git_reference_dwim", closure: { pointer in
      git_reference_dwim(&pointer, repositoryPointer, refspec)
    })
    defer {
      git_reference_free(reference)
    }
    let treePointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
      git_reference_peel(&pointer, reference, GIT_OBJECT_TREE)
    })
    return Tree(treePointer)
  }

  public enum TreeWalkResult: Int32 {
    case skipSubtree = 1
    case `continue` = 0
    case done = -1
  }

  public typealias TreeWalkCallback = (TreeEntry) -> TreeWalkResult

  public func treeWalk(
    tree: Tree,
    traversalMode: git_treewalk_mode = GIT_TREEWALK_PRE,
    callback: @escaping TreeWalkCallback
  ) throws {
    var callback = callback
    try withUnsafeMutablePointer(to: &callback) { callbackPointer in
      try GitError.check(apiName: "git_tree_walk", closure: {
        git_tree_walk(tree.treePointer, traversalMode, treeWalkCallback, callbackPointer)
      })
    }
  }

  public func treeWalk(
    tree: Tree? = nil,
    traversalMode: git_treewalk_mode = GIT_TREEWALK_PRE
  ) -> AsyncThrowingStream<TreeEntry, Error> {
    AsyncThrowingStream { continuation in
      do {
        let originTree = try (tree ?? (try headTree))
        try treeWalk(tree: originTree, traversalMode: traversalMode, callback: { qualifiedEntry in
          continuation.yield(qualifiedEntry)
          return .continue
        })
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  public func lookupBlob(for entry: TreeEntry) throws -> Data {
    let blobPointer = try GitError.checkAndReturn(apiName: "git_blob_lookup", closure: { pointer in
      var oid = entry.objectID.oid
      return git_blob_lookup(&pointer, repositoryPointer, &oid)
    })
    defer {
      git_blob_free(blobPointer)
    }
    let size = git_blob_rawsize(blobPointer)
    let data = Data(bytes: git_blob_rawcontent(blobPointer), count: Int(size))
    return data
  }

  // TODO: Refactor shared code with the TreeEntry version
  public func lookupBlob(for entry: git_index_entry) throws -> Data {
    let blobPointer = try GitError.checkAndReturn(apiName: "git_blob_lookup", closure: { pointer in
      var oid = entry.id
      return git_blob_lookup(&pointer, repositoryPointer, &oid)
    })
    defer {
      git_blob_free(blobPointer)
    }
    let size = git_blob_rawsize(blobPointer)
    let data = Data(bytes: git_blob_rawcontent(blobPointer), count: Int(size))
    return data
  }

  public func lookupCommit(for id: ObjectID) throws -> Commit {
    var objectID = id.oid
    let commitPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { pointer in
      git_commit_lookup(&pointer, repositoryPointer, &objectID)
    })
    return Commit(commitPointer)
  }

  public func add(_ pathspec: String = "*") throws {
    let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
      git_repository_index(&pointer, repositoryPointer)
    })
    defer {
      git_index_free(indexPointer)
    }
    var dirPointer = UnsafeMutablePointer<Int8>(mutating: (pathspec as NSString).utf8String)
    var paths = withUnsafeMutablePointer(to: &dirPointer) {
      git_strarray(strings: $0, count: 1)
    }

    try GitError.check(apiName: "git_index_add_all", closure: {
      git_index_add_all(indexPointer, &paths, 0, nil, nil)
    })
    try GitError.check(apiName: "git_index_write", closure: {
      git_index_write(indexPointer)
    })
  }

  public func addData(_ data: Data, path: String) throws {
    try path.withCString { pathPointer in
      var indexEntry = git_index_entry()
      indexEntry.path = pathPointer
      let now = Date()
      let indexTime = git_index_time(seconds: Int32(now.timeIntervalSince1970), nanoseconds: 0)
      indexEntry.ctime = indexTime
      indexEntry.mtime = indexTime
      indexEntry.mode = 0o100644
      let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
        git_repository_index(&pointer, repositoryPointer)
      })
      defer {
        git_index_free(indexPointer)
      }
      try data.withUnsafeBytes { bufferPointer in
        try GitError.check(apiName: "git_index_add_from_buffer", closure: {
          git_index_add_from_buffer(indexPointer, &indexEntry, bufferPointer.baseAddress, data.count)
        })
      }
    }
  }

  @discardableResult
  public func commit(message: String, signature: Signature) throws -> ObjectID {
    let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
      git_repository_index(&pointer, repositoryPointer)
    })
    defer {
      git_index_free(indexPointer)
    }

    var parentCommitPointer: OpaquePointer?
    var referencePointer: OpaquePointer?
    try GitError.check(apiName: "git_revparse_ext", closure: {
      let result = git_revparse_ext(&parentCommitPointer, &referencePointer, repositoryPointer, "HEAD")
      // Remap "ENOTFOUND" to "OK" because things work just fine if there is no HEAD commit; it means we're making
      // the first commit in the repo.
      if result == GIT_ENOTFOUND.rawValue {
        return GIT_OK.rawValue
      }
      return result
    })
    if referencePointer != nil {
      git_reference_free(referencePointer)
    }
    defer {
      if parentCommitPointer != nil {
        git_commit_free(parentCommitPointer)
      }
    }

    // Take the contents of the index & write it to the object database as a tree.
    let treeOID = try GitError.checkAndReturnOID(apiName: "git_index_write_tree", closure: { oid in
      git_index_write_tree(&oid, indexPointer)
    })
    let tree = try lookupTree(for: treeOID)

    return try GitError.checkAndReturnOID(apiName: "git_commit_create", closure: { commitOID in
      git_commit_create(
        &commitOID,
        repositoryPointer,
        "HEAD",
        signature.signaturePointer,
        signature.signaturePointer,
        nil,
        message,
        tree.treePointer,
        parentCommitPointer != nil ? 1 : 0, &parentCommitPointer
      )
    })
  }

  /// Pushes refspecs to a remote, returning an `AsyncThrowingStream` that you can use to track progress.
  /// - Parameters:
  ///   - remoteName: The remote to push to.
  ///   - refspecs: The references to push.
  ///   - credentials: The credentials to use for connect to the remote.
  /// - Returns: An `AsyncThrowingStream` that emits ``PushProgress`` structs for tracking progress.
  public func pushProgress(remoteName: String, refspecs: [String], credentials: Credentials = .default) -> AsyncThrowingStream<PushProgress, Error> {
    let pushOptions = PushOptions(credentials: credentials)
    let stream = AsyncThrowingStream<PushProgress, Error> { continuation in
      pushOptions.progressCallback = { progress in
        continuation.yield(progress)
      }
      do {
        let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_lookup", closure: { pointer in
          git_remote_lookup(&pointer, repositoryPointer, remoteName)
        })
        defer {
          git_remote_free(remotePointer)
        }
        var refspecPointers = refspecs.map { pushRefspec in
          let dirPointer = UnsafeMutablePointer<Int8>(mutating: (pushRefspec as NSString).utf8String)
          return dirPointer
        }
        let pointerCount = refspecPointers.count
        try refspecPointers.withUnsafeMutableBufferPointer { foo in
          var paths = git_strarray(strings: foo.baseAddress, count: pointerCount)
          try GitError.check(apiName: "git_remote_push", closure: {
            pushOptions.withOptions { options in
              git_remote_push(remotePointer, &paths, &options)
            }
          })
        }
        continuation.finish()
        Logger.repository.info("Done pushing")
      } catch {
        continuation.finish(throwing: error)
      }
    }
    return stream
  }

  public func push(remoteName: String, refspecs: [String], credentials: Credentials = .default) async throws {
    for try await _ in pushProgress(remoteName: remoteName, refspecs: refspecs, credentials: credentials) {}
  }

  public func enumerateCommits(revspec: String, callback: (Commit) -> Bool) throws {
    // TODO: Per the documentation, we should reuse this walker.
    let revwalkPointer = try GitError.checkAndReturn(apiName: "git_revwalk_new", closure: { pointer in
      git_revwalk_new(&pointer, repositoryPointer)
    })
    defer {
      git_revwalk_free(revwalkPointer)
    }
    let commitPointer = try GitError.checkAndReturn(apiName: "git_revparse_single", closure: { commitPointer in
      git_revparse_single(&commitPointer, repositoryPointer, revspec)
    })
    defer {
      git_commit_free(commitPointer)
    }
    try GitError.check(apiName: "git_revwalk_push", closure: {
      let oid = git_commit_id(commitPointer)
      return git_revwalk_push(revwalkPointer, oid)
    })
    var oid = git_oid()
    var walkResult = git_revwalk_next(&oid, revwalkPointer)
    var stop = false
    while walkResult == 0, !stop {
      let historyCommitPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { historyCommitPointer in
        git_commit_lookup(&historyCommitPointer, repositoryPointer, &oid)
      })
      stop = !callback(Commit(historyCommitPointer))
      walkResult = git_revwalk_next(&oid, revwalkPointer)
    }
    if walkResult != GIT_ITEROVER.rawValue, !stop {
      throw GitError(errorCode: walkResult, apiName: "git_revwalk_next")
    }
  }

  /// Get the history of changes to the repository.
  /// - Parameter revspec: The starting commit for history.
  /// - Returns: An `AsyncThrowingStream` whose elements are ``Commit`` records starting at `revspec`.
  public func log(revspec: String) -> AsyncThrowingStream<Commit, Error> {
    AsyncThrowingStream { continuation in
      do {
        try enumerateCommits(revspec: revspec) { commit in
          continuation.yield(commit)
          return true
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  public func allCommits(revspec: String) throws -> [Commit] {
    var results: [Commit] = []
    try enumerateCommits(revspec: revspec) { commit in
      results.append(commit)
      return true
    }
    return results
  }

  public func isCommitReachableFromAnyRemote(commit: Commit) throws -> Bool {
    let remoteOids = try branches(type: .remote).compactMap { branchName -> git_oid? in
      try lookupReference(name: branchName)?.commit.objectID.oid
    }
    var commitOid = commit.objectID.oid
    let isReachable = git_graph_reachable_from_any(repositoryPointer, &commitOid, remoteOids, remoteOids.count)
    switch isReachable {
    case 1:
      return true
    case 0:
      return false
    default:
      throw GitError(errorCode: isReachable, apiName: "git_graph_reachable_from_any")
    }
  }

  public func diff(_ oldTree: Tree?, _ newTree: Tree?) throws -> Diff {
    let diffPointer = try GitError.checkAndReturn(apiName: "git_diff_tree_to_tree", closure: { pointer in
      git_diff_tree_to_tree(&pointer, repositoryPointer, oldTree?.treePointer, newTree?.treePointer, nil)
    })
    return Diff(diffPointer)
  }
}

private func treeWalkCallback(root: UnsafePointer<Int8>?, entryPointer: OpaquePointer?, payload: UnsafeMutableRawPointer?) -> Int32 {
  guard let payload = payload, let entryPointer = entryPointer, let root = root else {
    return Repository.TreeWalkResult.continue.rawValue
  }
  let callbackPointer = payload.assumingMemoryBound(to: Repository.TreeWalkCallback.self)
  let entry = TreeEntry(entryPointer, root: String(cString: root))
  return callbackPointer.pointee(entry).rawValue
}
