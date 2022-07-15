// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

public final class Diff {
  init(_ diffPointer: OpaquePointer) {
    self.diffPointer = diffPointer
    self.deltaCount = git_diff_num_deltas(diffPointer)
  }

  deinit {
    git_diff_free(diffPointer)
  }

  let diffPointer: OpaquePointer
  let deltaCount: Int

  public struct Delta {
    public let status: Status
    public let flags: Flags
    public let oldFile: File
    public let newFile: File

    init(_ delta: git_diff_delta) {
      self.status = Status(rawValue: delta.status.rawValue) ?? .unreadable
      self.flags = Flags(rawValue: delta.flags)
      self.oldFile = File(delta.old_file)
      self.newFile = File(delta.new_file)
    }
  }

  public enum Status: UInt32 {
    case unmodified = 0 /** < no changes */
    case added = 1 /** < entry does not exist in old version */
    case deleted = 2 /** < entry does not exist in new version */
    case modified = 3 /** < entry content changed between old and new */
    case renamed = 4 /** < entry was renamed between old and new */
    case copied = 5 /** < entry was copied from another old entry */
    case ignored = 6 /** < entry is ignored item in workdir */
    case untracked = 7 /** < entry is untracked item in workdir */
    case typechange = 8 /** < type of entry changed between old and new */
    case unreadable = 9 /** < entry is unreadable */
    case conflicted = 10 /** < entry in the index is conflicted */
  }

  public struct Flags: RawRepresentable, OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
      self.rawValue = rawValue
    }

    public static let binary = Flags(rawValue: 1 << 0) /** < file(s) treated as binary data */
    public static let notBinary = Flags(rawValue: 1 << 1) /** < file(s) treated as text data */
    public static let validId = Flags(rawValue: 1 << 2) /** < `id` value is known correct */
    public static let exists = Flags(rawValue: 1 << 3) /** < file exists at this side of the delta */
  }

  public struct File {
    public let id: ObjectID
    public let path: String
    public let size: Int
    public let flags: Flags

    public init(_ gitFile: git_diff_file) {
      self.id = ObjectID(gitFile.id)
      self.path = String(cString: gitFile.path)
      self.size = Int(gitFile.size)
      self.flags = Flags(rawValue: UInt32(gitFile.flags))
    }
  }
}

extension Diff: RandomAccessCollection {
  public var startIndex: Int { 0 }
  public var endIndex: Int { deltaCount }

  public func index(after i: Int) -> Int {
    i + 1
  }

  public func index(before i: Int) -> Int {
    i - 1
  }

  public subscript(position: Int) -> Delta {
    Delta(git_diff_get_delta(diffPointer, position)!.pointee)
  }
}
