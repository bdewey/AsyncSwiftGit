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
}

extension Commit: CustomStringConvertible {
  public var description: String {
    "\(objectID) \(ISO8601DateFormatter().string(from: commitTime)) \(summary)"
  }
}
