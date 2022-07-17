// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

public final class Reference {
  init(pointer: OpaquePointer) {
    self.referencePointer = pointer
  }

  deinit {
    git_reference_free(referencePointer)
  }

  let referencePointer: OpaquePointer

  public var name: String? {
    if let charPointer = git_reference_name(referencePointer) {
      return String(cString: charPointer)
    } else {
      return nil
    }
  }

  public var commit: Commit {
    get throws {
      let commitPointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { commitPointer in
        git_reference_peel(&commitPointer, referencePointer, GIT_OBJECT_COMMIT)
      })
      return Commit(commitPointer)
    }
  }

  public var tree: Tree {
    get throws {
      let treePointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { pointer in
        git_reference_peel(&pointer, referencePointer, GIT_OBJECT_TREE)
      })
      return Tree(treePointer)
    }
  }

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
