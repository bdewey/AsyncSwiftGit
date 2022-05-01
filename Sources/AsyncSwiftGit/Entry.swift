import Clibgit2
import Foundation

/// Contains the properties of a `git_tree_entry`
public struct Entry {
  init(_ entry: OpaquePointer) {
    self.name = String(validatingUTF8: git_tree_entry_name(entry)) ?? "nil"
  }

  public let name: String
}
