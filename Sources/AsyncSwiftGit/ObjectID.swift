import Clibgit2
import Foundation

/// Make a `git_oid` more Swifty
public struct ObjectID: CustomStringConvertible {
  init(_ oid: git_oid) {
    self.oid = oid
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
