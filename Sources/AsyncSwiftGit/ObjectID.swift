import Clibgit2
import Foundation

/// Make a `git_oid` more Swifty
public struct ObjectID: CustomStringConvertible {
  init(_ oid: git_oid) {
    self.oid = oid
  }

  init?(_ oidPointer: UnsafePointer<git_oid>?) {
    guard let oid = oidPointer?.pointee else {
      return nil
    }
    self.init(oid)
  }

  let oid: git_oid

  public var description: String {
    let length = Int(GIT_OID_RAWSZ) * 2
    let string = UnsafeMutablePointer<Int8>.allocate(capacity: length)
    var oid = self.oid
    git_oid_fmt(string, &oid)

    return String(bytesNoCopy: string, length: length, encoding: .ascii, freeWhenDone: true) ?? "<error>"
  }
}

extension ObjectID: Equatable {
  public static func == (lhs: ObjectID, rhs: ObjectID) -> Bool {
    return lhs.description == rhs.description
  }
}
