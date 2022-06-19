// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

import Clibgit2
import Foundation
import Logging

private extension Logger {
  static let push: Logger = {
    var logger = Logger(label: "org.brians-brain.AsyncSwiftGit.PushOptions")
    logger[metadataKey: "subsystem"] = "push"
    logger.logLevel = .trace
    return logger
  }()
}

public enum PushProgress {
  case sideband(String)
  case push(current: Int, total: Int, bytes: Int)
}

final class PushOptions: CustomStringConvertible {
  typealias ProgressBlock = (PushProgress) -> Void

  init(credentials: Credentials = .default, progressCallback: ProgressBlock? = nil) {
    self.credentials = credentials
    self.progressCallback = progressCallback
  }

  var credentials: Credentials
  var progressCallback: ProgressBlock?

  var description: String {
    "FetchOptions Credentials = \(credentials), progressCallback \(progressCallback != nil ? "is not nil" : "is nil")"
  }

  func toPointer() -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(self).toOpaque()
  }

  static func fromPointer(_ pointer: UnsafeMutableRawPointer) -> PushOptions {
    Unmanaged<PushOptions>.fromOpaque(UnsafeRawPointer(pointer)).takeUnretainedValue()
  }

  func withOptions<T>(closure: (inout git_push_options) throws -> T) rethrows -> T {
    var options = git_push_options()
    git_push_options_init(&options, UInt32(GIT_PUSH_OPTIONS_VERSION))
    if progressCallback != nil {
      options.callbacks.sideband_progress = sidebandProgress
      options.callbacks.push_transfer_progress = pushProgress
    }
    options.callbacks.payload = toPointer()
    options.callbacks.credentials = credentialsCallback
    return try closure(&options)
  }
}

private func sidebandProgress(message: UnsafePointer<Int8>?, length: Int32, payload: UnsafeMutableRawPointer?) -> Int32 {
  guard let payload = payload else {
    return 0
  }
  let pushOptions = PushOptions.fromPointer(payload)
  if let message = message {
    let string = String(cString: message)
    pushOptions.progressCallback?(.sideband(string))
  }
  return 0
}

private func pushProgress(current: UInt32, total: UInt32, bytes: Int, payload: UnsafeMutableRawPointer?) -> Int32 {
  guard let payload = payload else {
    return 0
  }

  let pushOptions = PushOptions.fromPointer(payload)
  pushOptions.progressCallback?(.push(current: Int(current), total: Int(total), bytes: Int(bytes)))
  return 0
}
