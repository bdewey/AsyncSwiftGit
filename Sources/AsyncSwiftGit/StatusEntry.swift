// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

public struct StatusEntry: Hashable {
  public struct Status: RawRepresentable, OptionSet, Hashable {
    public var rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public init(_ gitStatus: git_status_t) {
      self.rawValue = Int(gitStatus.rawValue)
    }

    public static let current = Status([])
    public static let indexHeadNew = Status(rawValue: 1 << 0)
    public static let indexHeadModified = Status(rawValue: 1 << 1)
    public static let indexHeadDeleted = Status(rawValue: 1 << 2)
    public static let indexHeadRenamed = Status(rawValue: 1 << 3)
    public static let indexHeadTypechange = Status(rawValue: 1 << 4)

    public static let workdirIndexNew = Status(rawValue: 1 << 7)
    public static let workdirIndexModified = Status(rawValue: 1 << 8)
    public static let workdirIndexDeleted = Status(rawValue: 1 << 9)
    public static let workdirIndexTypechange = Status(rawValue: 1 << 10)
    public static let workdirIndexRenamed = Status(rawValue: 1 << 11)
    public static let workdirIndexUnreadable = Status(rawValue: 1 << 12)

    public static let ignored = Status(rawValue: 1 << 14)
    public static let conflicted = Status(rawValue: 1 << 15)
  }

  public enum PathPair: Hashable {
    case renamed(oldPath: String, newPath: String)
    case constant(path: String)

    public var isRenamed: Bool {
      switch self {
      case .renamed:
        return true
      case .constant:
        return false
      }
    }

    public var oldPath: String {
      switch self {
      case .renamed(oldPath: let oldPath, _):
        return oldPath
      case .constant(path: let path):
        return path
      }
    }

    public var newPath: String {
      switch self {
      case .renamed(_, newPath: let newPath):
        return newPath
      case .constant(path: let path):
        return path
      }
    }

    public init?(_ delta: UnsafeMutablePointer<git_diff_delta>?) {
      guard let delta = delta else {
        return nil
      }
      let oldPath = delta.pointee.old_file.path.flatMap { String(cString: $0) }
      let newPath = delta.pointee.new_file.path.flatMap { String(cString: $0) }

      switch (oldPath, newPath) {
      case (.none, .none):
        return nil
      case (.some(let path), .none):
        self = .constant(path: path)
      case (.none, .some(let path)):
        self = .constant(path: path)
      case (.some(let oldPath), .some(let newPath)):
        self = .renamed(oldPath: oldPath, newPath: newPath)
      }
    }
  }

  public var headToIndexPath: PathPair?
  public var indexToWorkdirPath: PathPair?
  public var status: Status

  public init?(_ gitStatusEntry: git_status_entry) {
    let status = Status(gitStatusEntry.status)
    guard status != .current else {
      return nil
    }
    self.status = status
    self.headToIndexPath = PathPair(gitStatusEntry.head_to_index)
    self.indexToWorkdirPath = PathPair(gitStatusEntry.index_to_workdir)
    if headToIndexPath == nil, indexToWorkdirPath == nil {
      return nil
    }
  }

  public var path: String {
    let returnValue = headToIndexPath?.newPath ?? indexToWorkdirPath?.newPath
    return returnValue!
  }
}

extension StatusEntry: CustomStringConvertible {
  public var description: String {
    "\(path) \(status)"
  }
}
