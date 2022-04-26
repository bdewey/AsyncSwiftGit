import Clibgit2
import Foundation

/// Represents an error from an internal Clibgit2 API call.
public struct GitError: Error {
  /// The numeric error code from the Git API.
  public let errorCode: Int32

  /// The name of the API that returned the error.
  public let apiName: String

  /// A human-readable error message.
  public let message: String

  /// Initializer. Must be called on the same thread as the API call that generated the error to properly get the error message.
  init(errorCode: Int32, apiName: String) {
    self.errorCode = errorCode
    self.apiName = apiName
    if let lastErrorPointer = git_error_last() {
      self.message = String(validatingUTF8: lastErrorPointer.pointee.message) ?? "invalid message"
    } else if errorCode == GIT_ERROR_OS.rawValue {
      self.message = String(validatingUTF8: strerror(errno)) ?? "invalid message"
    } else {
      self.message = "Unknown"
    }
  }

  /// Invokes a closure that invokes a Git API call and throws a `GitError` if the closure returns anything other than `GIT_OK`.
  static func check(apiName: String, closure: () -> Int32) throws {
    let result = closure()
    guard result == GIT_OK.rawValue else {
      throw GitError(errorCode: result, apiName: apiName)
    }
  }
}
