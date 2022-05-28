import Clibgit2
import Foundation

extension git_merge_analysis_t: OptionSet {}

/// A Git repository.
public actor Repository {
  public typealias CloneProgressBlock = (Double) -> Void

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
        git_repository_init(&pointer, fileSystemPath, bare ? 1 : 0)
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
    credentials: Credentials = .default,
    progress: CloneProgressBlock? = nil
  ) async throws -> Repository {
    let repositoryPointer = try await Task { () -> OpaquePointer in
      let cloneOptions = CloneOptions(
        fetchOptions: FetchOptions(credentials: credentials, progressCallback: progress)
      )
      return try cloneOptions.withOptions { options -> OpaquePointer in
        var options = options
        return try GitError.checkAndReturn(apiName: "git_clone", closure: { pointer in
          localURL.withUnsafeFileSystemRepresentation { filePath in
            git_clone(&pointer, remoteURL.absoluteString, filePath, &options)
          }
        })
      }
    }.value
    return Repository(repositoryPointer: repositoryPointer)
  }

  /// Fetch from a named remote.
  /// - Parameters:
  ///   - remote: The remote to fetch
  ///   - credentials: Credentials to use for the fetch.
  public func fetch(remote: String, credentials: Credentials = .default) throws {
    let fetchOptions = FetchOptions(credentials: credentials, progressCallback: nil)
    let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_lookup", closure: { pointer in
      git_remote_lookup(&pointer, repositoryPointer, remote)
    })
    defer {
      git_remote_free(remotePointer)
    }
    try GitError.check(apiName: "git_remote_fetch", closure: {
      fetchOptions.withOptions { options in
        git_remote_fetch(remotePointer, nil, &options, "fetch")
      }
    })
  }

  /// Merge a `ref` into the current branch.
  public func merge(revspec: String) throws {
    // Throw an error if we are in any non-normal state (e.g., cherry-pick)
    try GitError.check(apiName: "git_repository_state", closure: {
      git_repository_state(repositoryPointer)
    })

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
    print("analysis = \(analysis) mergePreference = \(mergePreference)")
    if analysis.contains(GIT_MERGE_ANALYSIS_FASTFORWARD), let oid = ObjectID(git_annotated_commit_id(annotatedCommit)) {
      print("Doing a fast-forward")
      try fastForward(to: oid, isUnborn: analysis.contains(GIT_MERGE_ANALYSIS_UNBORN))
    }
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

  private var head: Reference {
    get throws {
      let reference = try GitError.checkAndReturn(apiName: "git_repository_head", closure: { pointer in
        git_repository_head(&pointer, repositoryPointer)
      })
      return Reference(pointer: reference)
    }
  }

  public func addRemote(_ name: String, url: URL) throws {
    let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_create", closure: { pointer in
      git_remote_create(&pointer, repositoryPointer, name, url.absoluteString)
    })
    git_remote_free(remotePointer)
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

  public func push(credentials: Credentials = .default) throws {
    let remotePointer = try GitError.checkAndReturn(apiName: "git_remote_lookup", closure: { pointer in
      git_remote_lookup(&pointer, repositoryPointer, "origin")
    })
    defer {
      git_remote_free(remotePointer)
    }
    let pushOptions = PushOptions(credentials: credentials)
    #warning("This doesn't look up the right ref")
    var dirPointer = UnsafeMutablePointer<Int8>(mutating: ("refs/heads/main" as NSString).utf8String)
    var paths = withUnsafeMutablePointer(to: &dirPointer) {
      git_strarray(strings: $0, count: 1)
    }
    try GitError.check(apiName: "git_remote_push", closure: {
      pushOptions.withOptions { options in
        git_remote_push(remotePointer, &paths, &options)
      }
    })
  }
}
