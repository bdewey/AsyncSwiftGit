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

/// A value that represents progress towards a goal.
public enum Progress<ProgressType, ResultType> {
  /// Progress towards the goal, storing the progress value.
  case progress(ProgressType)

  /// The goal is completed, storing the resulting goal value.
  case completed(ResultType)
}

/// A Git repository.
public final class Repository {
  typealias FetchProgressBlock = (FetchProgress) -> Void
  typealias CloneProgressBlock = (Result<Double, Error>) -> Void

  /// The Clibgit2 repository pointer managed by this actor.
  private let repositoryPointer: OpaquePointer

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
    self.init(repositoryPointer: repositoryPointer)
  }

  /// Opens a git repository at a specified location.
  /// - Parameter url: The location of the repository to open.
  public convenience init(openAt url: URL) throws {
    let repositoryPointer = try GitError.checkAndReturn(apiName: "git_repository_open") { pointer in
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        git_repository_open(&pointer, fileSystemPath)
      }
    }
    self.init(repositoryPointer: repositoryPointer)
  }

  private init(repositoryPointer: OpaquePointer) {
    self.repositoryPointer = repositoryPointer
    if let pathPointer = git_repository_workdir(repositoryPointer), let path = String(validatingUTF8: pathPointer) {
      self.workingDirectoryURL = URL(fileURLWithPath: path, isDirectory: true)
    } else {
      self.workingDirectoryURL = nil
    }
  }

  deinit {
    git_repository_free(repositoryPointer)
  }

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
        continuation.yield(.completed(Repository(repositoryPointer: repositoryPointer)))
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  /// Returns the URL associated with a particular git remote name.
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

  /// Adds a named remote to the repo.
  public func addRemote(_ name: String, url: URL) throws {
    let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_create", closure: { pointer in
      git_remote_create(&pointer, repositoryPointer, name, url.absoluteString)
    })
    git_remote_free(remotePointer)
  }

  /// Deletes the named remote from the reposityr.
  public func deleteRemote(_ name: String) throws {
    try GitError.check(apiName: "git_remote_delete", closure: {
      git_remote_delete(repositoryPointer, name)
    })
  }

  /// Fetch from a named remote.
  /// - Parameters:
  ///   - remote: The remote to fetch
  ///   - credentials: Credentials to use for the fetch.
  /// - returns: An AsyncThrowingStream that emits the fetch progress. The fetch is not done until this stream finishes yielding values.
  public func fetchProgress(remote: String, credentials: Credentials = .default) -> AsyncThrowingStream<FetchProgress, Error> {
    let fetchOptions = FetchOptions(credentials: credentials, progressCallback: nil)
    let resultStream = AsyncThrowingStream<FetchProgress, Error> { continuation in
      fetchOptions.progressCallback = { progressResult in
        continuation.yield(progressResult)
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
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    return resultStream
  }

  /// Fetch from a named remote, waiting until the fetch is 100% complete before returning.
  /// - Parameters:
  ///   - remote: The remote to fetch
  ///   - credentials: Credentials to use for the fetch.
  public func fetch(remote: String, credentials: Credentials = .default) async throws {
    for try await _ in fetchProgress(remote: remote, credentials: credentials) {}
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
  public func merge(revspec: String, signature signatureBlock: @autoclosure () throws -> Signature) throws -> MergeResult {
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
      try checkForConflicts()
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

  private func countCommits(revspec: String) throws -> Int {
    var count = 0
    try enumerateCommits(revspec: revspec) { _ in
      count += 1
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

  private func commitMerge(revspec: String, annotatedCommit: OpaquePointer, signature: Signature) throws -> ObjectID {
    let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
      git_repository_index(&pointer, repositoryPointer)
    })
    defer {
      git_index_free(indexPointer)
    }
    let headReference = try head
    let headCommit = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
      git_reference_peel(&pointer, headReference.pointer, GIT_OBJECT_COMMIT)
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
        git_reference_name(headReference.pointer),
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
    case hard

    var reset_type: git_reset_t {
      switch self {
      case .soft:
        return GIT_RESET_SOFT
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

  /// Throws ``ConflictError`` if there are conflicts in the current repository.
  public func checkForConflicts() throws {
    // See if there were conflicts
    let indexPointer = try GitError.checkAndReturn(apiName: "git_repository_index", closure: { pointer in
      git_repository_index(&pointer, repositoryPointer)
    })
    defer {
      git_index_free(indexPointer)
    }

    if git_index_has_conflicts(indexPointer) == 0 {
      // No conflicts
      return
    }

    let iteratorPointer = try GitError.checkAndReturn(apiName: "git_index_conflict_iterator_new", closure: { pointer in
      git_index_conflict_iterator_new(&pointer, indexPointer)
    })
    defer {
      git_index_conflict_iterator_free(iteratorPointer)
    }

    var ancestor: UnsafePointer<git_index_entry>?
    var ours: UnsafePointer<git_index_entry>?
    var theirs: UnsafePointer<git_index_entry>?

    var conflictingPaths: [String] = []

    while git_index_conflict_next(&ancestor, &ours, &theirs, iteratorPointer) == 0 {
      guard let pathChars = ours?.pointee.path ?? theirs?.pointee.path ?? ancestor?.pointee.path else {
        continue
      }
      let path = String(cString: pathChars)
      conflictingPaths.append(path)
    }

    throw ConflictError(conflictingPaths: conflictingPaths)
  }

  private func fastForward(to objectID: ObjectID, isUnborn: Bool) throws {
    let headReference = isUnborn ? try createSymbolicReference(named: "HEAD", targeting: objectID) : try head
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
      return git_reference_set_target(&pointer, headReference.pointer, &oid, nil)
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

  public var head: Reference {
    get throws {
      let reference = try GitError.checkAndReturn(apiName: "git_repository_head", closure: { pointer in
        git_repository_head(&pointer, repositoryPointer)
      })
      return Reference(pointer: reference)
    }
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
  public func lookupTree(for entry: Entry) throws -> Tree {
    try lookupTree(for: entry.objectID)
  }

  public func lookupTree(for objectID: ObjectID) throws -> Tree {
    let treePointer = try GitError.checkAndReturn(apiName: "git_tree_lookup", closure: { pointer in
      var oid = objectID.oid
      return git_tree_lookup(&pointer, repositoryPointer, &oid)
    })
    return Tree(treePointer)
  }

  /// Returns a sequence of all entries found in `Tree` and all of its children.
  public func entries(tree: Tree) -> TreeEntrySequence {
    TreeEntrySequence(repository: self, tree: tree)
  }

  public func lookupBlob(for entry: Entry) throws -> Data {
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

  public func pushProgress(credentials: Credentials = .default) throws -> AsyncThrowingStream<PushProgress, Error> {
    guard let head = try? head else {
      // Assume that if we can't get HEAD, it's because the repo is empty. Ergo, nothing to push.
      return AsyncThrowingStream { continuation in
        continuation.finish()
      }
    }
    let pushOptions = PushOptions(credentials: credentials)
    let stream = AsyncThrowingStream<PushProgress, Error> { continuation in
      pushOptions.progressCallback = { progress in
        continuation.yield(progress)
      }
      do {
        let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_lookup", closure: { pointer in
          git_remote_lookup(&pointer, repositoryPointer, "origin")
        })
        defer {
          git_remote_free(remotePointer)
        }
        guard let headName = head.name else {
          throw GitError(errorCode: -312, apiName: "git_remote_push", customMessage: "Could not determine the name of the current branch")
        }
        var dirPointer = UnsafeMutablePointer<Int8>(mutating: (headName as NSString).utf8String)
        var paths = withUnsafeMutablePointer(to: &dirPointer) {
          git_strarray(strings: $0, count: 1)
        }
        try GitError.check(apiName: "git_remote_push", closure: {
          pushOptions.withOptions { options in
            git_remote_push(remotePointer, &paths, &options)
          }
        })
        continuation.finish()
        Logger.repository.info("Done pushing")
      } catch {
        continuation.finish(throwing: error)
      }
    }
    return stream
  }

  public func push(credentials: Credentials = .default) async throws {
    for try await _ in try pushProgress(credentials: credentials) {}
  }

  public func enumerateCommits(revspec: String, callback: (Commit) -> Void) throws {
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
    while walkResult == 0 {
      let historyCommitPointer = try GitError.checkAndReturn(apiName: "git_commit_lookup", closure: { historyCommitPointer in
        git_commit_lookup(&historyCommitPointer, repositoryPointer, &oid)
      })
      callback(Commit(historyCommitPointer))
      walkResult = git_revwalk_next(&oid, revwalkPointer)
    }
    if walkResult != GIT_ITEROVER.rawValue {
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
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }
}
