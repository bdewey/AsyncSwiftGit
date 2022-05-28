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
}
