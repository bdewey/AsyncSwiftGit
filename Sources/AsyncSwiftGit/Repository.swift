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
    progress: CloneProgressBlock? = nil
  ) async throws -> Repository {
    let repositoryPointer = try await Task { () -> OpaquePointer in
      var options = CloneOptions(
        fetchOptions: FetchOptions(progressCallback: progress)
      ).makeOptions()
      return try GitError.checkAndReturn(apiName: "git_clone", closure: { pointer in
        localURL.withUnsafeFileSystemRepresentation { filePath in
          git_clone(&pointer, remoteURL.absoluteString, filePath, &options)
        }
      })
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
    let treePointer = try GitError.checkAndReturn(apiName: "git_tree_lookup", closure: { pointer in
      var oid = entry.objectID.oid
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
}
