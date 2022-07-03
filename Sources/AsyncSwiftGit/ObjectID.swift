// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

/// Make a `git_oid` more Swifty
public struct ObjectID: CustomStringConvertible, Hashable {
  init(_ oid: git_oid) {
    self.oid = oid
  }

  init?(_ oidPointer: UnsafePointer<git_oid>?) {
    guard let oid = oidPointer?.pointee else {
      return nil
    }
    self.init(oid)
  }

  var oid: git_oid

  public var description: String {
    let length = Int(GIT_OID_RAWSZ) * 2
    let string = UnsafeMutablePointer<Int8>.allocate(capacity: length)
    var oid = oid
    git_oid_fmt(string, &oid)

    return String(bytesNoCopy: string, length: length, encoding: .ascii, freeWhenDone: true) ?? "<error>"
  }

  public func hash(into hasher: inout Hasher) {
    // so tedious...
    hasher.combine(oid.id.0)
    hasher.combine(oid.id.1)
    hasher.combine(oid.id.2)
    hasher.combine(oid.id.3)
    hasher.combine(oid.id.4)
    hasher.combine(oid.id.5)
    hasher.combine(oid.id.6)
    hasher.combine(oid.id.7)
    hasher.combine(oid.id.8)
    hasher.combine(oid.id.9)
    hasher.combine(oid.id.10)
    hasher.combine(oid.id.11)
    hasher.combine(oid.id.12)
    hasher.combine(oid.id.13)
    hasher.combine(oid.id.14)
    hasher.combine(oid.id.15)
    hasher.combine(oid.id.16)
    hasher.combine(oid.id.17)
    hasher.combine(oid.id.18)
    hasher.combine(oid.id.19)
  }
}

extension ObjectID: Equatable {
  public static func == (lhs: ObjectID, rhs: ObjectID) -> Bool {
    lhs.description == rhs.description
  }
}
