import Clibgit2
import Foundation

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
  public func commit(message: String) throws -> ObjectID {
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

    // make a default signature
    #warning("Need to get the real username / email")
    let signature = try Signature(name: "Brian Dewey", email: "bdewey@gmail.com")

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
