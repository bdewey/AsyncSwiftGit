import Clibgit2
import Foundation

/// Contains the properties of a `git_tree_entry`
public struct Entry {
  init(_ entry: OpaquePointer) {
    self.objectID = ObjectID(git_tree_entry_id(entry)!.pointee)
    self.name = String(validatingUTF8: git_tree_entry_name(entry)) ?? "nil"
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

extension Entry: CustomStringConvertible {
  public var description: String {
    return description(treePathSegments: [])
  }

  /// Prints a formatted description of this entry.
  /// - parameter pathPrefix: The array of `Tree` entry names that lead to the `Tree` that contains this entry.
  public func description(treePathSegments: [String]) -> String {
    var treePathSegments = treePathSegments
    treePathSegments.append(name)
    let fullName = treePathSegments.joined(separator: "/")
    return "\(objectID) \(type) \(fullName)"
  }
}
