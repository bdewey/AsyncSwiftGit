import Clibgit2
import Foundation

/// A Git repository.
public actor Repository {
  /// The Clibgit2 repository pointer managed by this actor.
  private let repositoryPointer: OpaquePointer

  /// Creates a Git repository at a location.
  /// - Parameters:
  ///   - url: The location to create a Git repository at.
  ///   - bare: Whether the repository should be "bare". A bare repository does not have a corresponding working directory.
  public init(createAt url: URL, bare: Bool = false) throws {
    var pointer: OpaquePointer?
    try GitError.check(apiName: "git_repository_init") {
      url.withUnsafeFileSystemRepresentation { fileSystemPath in
        git_repository_init(&pointer, fileSystemPath, bare ? 1 : 0)
      }
    }
    self.repositoryPointer = pointer!
  }

  deinit {
    git_repository_free(repositoryPointer)
  }
}
