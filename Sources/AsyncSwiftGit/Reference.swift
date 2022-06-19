// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

import Clibgit2
import Foundation

public final class Reference {
  init(pointer: OpaquePointer) {
    self.pointer = pointer
  }

  deinit {
    git_reference_free(pointer)
  }

  let pointer: OpaquePointer

  public var name: String? {
    if let charPointer = git_reference_name(pointer) {
      return String(cString: charPointer)
    } else {
      return nil
    }
  }

  public var commit: Commit {
    get throws {
      let commitPointer = try GitError.checkAndReturn(apiName: "git_reference_peel", closure: { commitPointer in
        git_reference_peel(&commitPointer, pointer, GIT_OBJECT_COMMIT)
      })
      return Commit(commitPointer)
    }
  }
}
