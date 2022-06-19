// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

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
}
