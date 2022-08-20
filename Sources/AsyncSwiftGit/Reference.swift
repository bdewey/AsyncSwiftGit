// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

/// In-memory representation of a reference.
public final class Reference {
  init(pointer: OpaquePointer) {
    self.referencePointer = pointer
  }

  deinit {
    git_reference_free(referencePointer)
  }

  let referencePointer: OpaquePointer

  /// The full name of the reference.
  public var name: String? {
    if let charPointer = git_reference_name(referencePointer) {
      return String(cString: charPointer)
    } else {
      return nil
    }
  }

  /// The first ``Commit`` object associated with this reference.
  public var commit: Commit {
    get throws {
      let commitPointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { commitPointer in
        git_reference_peel(&commitPointer, referencePointer, GIT_OBJECT_COMMIT)
      })
      return Commit(commitPointer)
    }
  }

  /// The first ``Tree`` object associated with this reference.
  public var tree: Tree {
    get throws {
      let treePointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
        git_reference_peel(&pointer, referencePointer, GIT_OBJECT_TREE)
      })
      return Tree(treePointer)
    }
  }

  /// The upstream reference for a branch.
  ///
  /// - note: This is only valid if the receiver is a branch reference.
  public var upstream: Reference? {
    get throws {
      do {
        let upstreamPointer = try GitError.checkAndReturn(apiName: "git_branch_upstream", closure: { pointer in
          git_branch_upstream(&pointer, referencePointer)
        })
        return Reference(pointer: upstreamPointer)
      } catch let error as GitError {
        if error.errorCode == GIT_ENOTFOUND.rawValue {
          return nil
        } else {
          throw error
        }
      }
    }
  }
}
