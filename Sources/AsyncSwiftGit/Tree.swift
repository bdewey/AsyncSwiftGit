// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

import Clibgit2
import Foundation

public final class Tree {
  init(_ treePointer: OpaquePointer) {
    self.treePointer = treePointer
    self.entryCount = git_tree_entrycount(treePointer)
  }

  deinit {
    git_object_free(treePointer)
  }

  let treePointer: OpaquePointer
  let entryCount: Int
}

extension Tree: BidirectionalCollection {
  public var startIndex: Int { 0 }
  public var endIndex: Int { entryCount }
  public func index(after i: Int) -> Int { i + 1 }
  public func index(before i: Int) -> Int { i - 1 }
  public var count: Int { entryCount }

  public subscript(position: Int) -> Entry {
    Entry(git_tree_entry_byindex(treePointer, position))
  }
}
