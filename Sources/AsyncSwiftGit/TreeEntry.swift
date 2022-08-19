// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

/// Contains the properties of a `git_tree_entry`
public struct TreeEntry: Hashable {
  /// Initializer.
  /// - Parameters:
  ///   - entry: The `git_tree_entry` containing the relevant properties.
  ///   - root: An optional path to the containing ``Tree`` for this entry.
  init(_ entry: OpaquePointer, root: String? = nil) {
    self.objectID = ObjectID(git_tree_entry_id(entry)!.pointee)
    let entryName = String(validatingUTF8: git_tree_entry_name(entry))
    if let root = root {
      assert(root.isEmpty || root.last == "/")
      self.name = root + (entryName ?? "")
    } else {
      self.name = entryName ?? ""
    }
    self.type = ObjectType(rawValue: git_tree_entry_type(entry).rawValue) ?? .invalid
  }

  /// The ObjectID associated with this entry.
  public let objectID: ObjectID

  /// The name for this entry.
  /// - note: The name is relative to the containing `Tree`
  public let name: String

  /// The type of this entry.
  public let type: ObjectType
}

extension TreeEntry: CustomStringConvertible {
  public var description: String {
    "\(objectID) \(type) \(name)"
  }
}
