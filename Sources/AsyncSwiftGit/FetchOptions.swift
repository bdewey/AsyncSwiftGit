import Clibgit2
import Foundation

final class FetchOptions: CustomStringConvertible {
  init(credentials: Credentials = .default, progressCallback: Repository.CloneProgressBlock? = nil) {
    self.credentials = credentials
    self.progressCallback = progressCallback
  }

  var credentials: Credentials
  var progressCallback: Repository.CloneProgressBlock?

  var description: String {
    "FetchOptions Credentials = \(credentials), progressCallback \(progressCallback != nil ? "is not nil" : "is nil")"
  }

  func toPointer() -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(self).toOpaque()
  }

  static func fromPointer(_ pointer: UnsafeMutableRawPointer) -> FetchOptions {
    Unmanaged<FetchOptions>.fromOpaque(UnsafeRawPointer(pointer)).takeUnretainedValue()
  }

  func withOptions<T>(closure: (inout git_fetch_options) throws -> T) rethrows -> T {
    var options = git_fetch_options()
    git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION))
    if progressCallback != nil {
      options.callbacks.transfer_progress = fetchProgress
    }
    options.callbacks.payload = toPointer()
    options.callbacks.credentials = credentialsCallback
    return try closure(&options)
  }
}

private func fetchProgress(progressPointer: UnsafePointer<git_indexer_progress>?, payload: UnsafeMutableRawPointer?) -> Int32 {
  guard let payload = payload else {
    return 0
  }

  let fetchOptions = FetchOptions.fromPointer(payload)
  if let progress = progressPointer?.pointee {
    let progressPercentage = (Double(progress.received_objects) + Double(progress.indexed_objects)) / (2 * Double(progress.total_objects))
    fetchOptions.progressCallback?(.success(progressPercentage))
  }
  return 0
}
