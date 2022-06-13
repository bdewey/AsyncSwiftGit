import Clibgit2
import Foundation

final class Reference {
  init(pointer: OpaquePointer) {
    self.pointer = pointer
  }

  deinit {
    git_reference_free(pointer)
  }

  let pointer: OpaquePointer

  var name: String? {
    if let charPointer = git_reference_name(pointer) {
      return String(cString: charPointer)
    } else {
      return nil
    }
  }
}
