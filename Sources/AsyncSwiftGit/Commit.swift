// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

/// A `git` commit.
public final class Commit {
  private var commit: OpaquePointer?

  init(_ commit: OpaquePointer) {
    self.commit = commit
  }

  deinit {
    git_commit_free(commit)
  }

  public var commitTime: Date {
    let git_time = git_commit_time(commit)
    return Date(timeIntervalSince1970: TimeInterval(git_time))
  }

  public var objectID: ObjectID {
    let oid = git_commit_id(commit)
    return ObjectID(oid)!
  }

  public var summary: String {
    if let result = git_commit_summary(commit) {
      return String(cString: result)
    } else {
      return ""
    }
  }

  public var tree: Tree {
    get throws {
      let treePointer = try GitError.checkAndReturn(apiName: "git_commit_tree", closure: { pointer in
        git_commit_tree(&pointer, commit)
      })
      return Tree(treePointer)
    }
  }

  public var parents: [Commit] {
    (0 ..< git_commit_parentcount(commit)).map { i in
      var parentCommitPointer: OpaquePointer?
      git_commit_parent(&parentCommitPointer, commit, UInt32(i))
      return Commit(parentCommitPointer!)
    }
  }

  public var changedPaths: Set<String> {
    get throws {
      let repository = Repository(repositoryPointer: git_commit_owner(commit), isOwner: false)
      var changedPaths: Set<String> = []
      let newTree = try tree
      for parent in parents {
        let oldTree = try parent.tree
        let diff = try repository.diff(oldTree, newTree)
        for delta in diff {
          changedPaths.insert(delta.oldFile.path)
          changedPaths.insert(delta.newFile.path)
        }
      }
      return changedPaths
    }
  }
}

extension Commit: CustomStringConvertible {
  public var description: String {
    "\(objectID) \(ISO8601DateFormatter().string(from: commitTime)) \(summary)"
  }
}
