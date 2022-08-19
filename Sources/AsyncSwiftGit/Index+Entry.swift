// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

public extension Index {
  enum EntryStage: Int {
    case normal = 0
    case ancestor = 1
    case ours = 2
    case theirs = 3
  }

  /// A Swift wrapper around `git_index_entry`
  struct Entry {
    public init(_ gitEntry: git_index_entry) {
      self.gitEntry = gitEntry
    }

    public init?(_ gitEntryPointer: UnsafePointer<git_index_entry>?) {
      guard let gitEntry = gitEntryPointer?.pointee else {
        return nil
      }
      self.init(gitEntry)
    }

    /// The git entry we wrap.
    public var gitEntry: git_index_entry

    /// The path represented by this entry.
    public var path: String {
      String(cString: gitEntry.path)
    }

    /// The object ID for this entry storied in the repository object database.
    public var objectID: ObjectID {
      ObjectID(gitEntry.id)
    }

    private let stageMask: UInt16 = 0x3000
    private let stageShift = 12

    public var stage: EntryStage {
      get {
        let rawValue = (gitEntry.flags & stageMask) >> stageShift
        return EntryStage(rawValue: Int(rawValue))!
      }
      set {
        gitEntry.flags = (gitEntry.flags & ~stageMask) | ((UInt16(newValue.rawValue) & 0x03) << stageShift)
      }
    }
  }

  /// A tuple of three ``Entry`` structures, at least one of which is guaranteed to be non-nil.
  struct ConflictEntry {
    public let ancestor: Entry?
    public let ours: Entry?
    public let theirs: Entry?

    /// Initializes a conflict entry. The initializer will fail if all of the related entries are nil.
    init?(ancestor: Entry? = nil, ours: Entry? = nil, theirs: Entry? = nil) {
      if ancestor == nil, ours == nil, theirs == nil {
        return nil
      }
      self.ancestor = ancestor
      self.ours = ours
      self.theirs = theirs
    }

    /// The path to the file that is in conflict.
    public var path: String {
      // At least one of these is guaranteed to be non-nil
      ours?.path ?? theirs?.path ?? ancestor!.path
    }
  }
}
