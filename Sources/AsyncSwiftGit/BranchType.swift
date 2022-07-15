// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

public struct BranchType: OptionSet {
  public var rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  public var gitType: git_branch_t {
    git_branch_t(rawValue: rawValue)
  }

  public static let local = BranchType(rawValue: GIT_BRANCH_LOCAL.rawValue)
  public static let remote = BranchType(rawValue: GIT_BRANCH_REMOTE.rawValue)
  public static let all: BranchType = [.local, .remote]
}
