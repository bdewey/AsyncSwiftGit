// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

import Clibgit2
import Foundation

/// Swift-y wrapper around `git_signature`
public final class Signature {
  public init(name: String, email: String, time: Date = Date(), timeZone: TimeZone = .current) throws {
    var signaturePointer: UnsafeMutablePointer<git_signature>?
    try GitError.check(apiName: "git_signature_new") {
      let gitTime = git_time_t(time.timeIntervalSince1970)
      let offset = Int32(timeZone.secondsFromGMT(for: time) / 60)
      return git_signature_new(&signaturePointer, name, email, gitTime, offset)
    }
    if let signaturePointer = signaturePointer {
      self.signaturePointer = signaturePointer
    } else {
      throw GitError(errorCode: GIT_ERROR.rawValue, apiName: "git_signature_new")
    }
  }

  deinit {
    git_signature_free(signaturePointer)
  }

  let signaturePointer: UnsafeMutablePointer<git_signature>
}
