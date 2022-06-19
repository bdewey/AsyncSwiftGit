// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

import Clibgit2
import Foundation

/// Represents an error from an internal Clibgit2 API call.
public struct GitError: Error, CustomStringConvertible, LocalizedError {
  /// The numeric error code from the Git API.
  public let errorCode: Int32

  /// The name of the API that returned the error.
  public let apiName: String

  /// A human-readable error message.
  public let message: String

  /// Initializer. Must be called on the same thread as the API call that generated the error to properly get the error message.
  init(errorCode: Int32, apiName: String, customMessage: String? = nil) {
    self.errorCode = errorCode
    self.apiName = apiName
    if let lastErrorPointer = git_error_last() {
      self.message = customMessage ?? String(validatingUTF8: lastErrorPointer.pointee.message) ?? "invalid message"
    } else if errorCode == GIT_ERROR_OS.rawValue {
      self.message = customMessage ?? String(validatingUTF8: strerror(errno)) ?? "invalid message"
    } else {
      self.message = customMessage ?? "Unknown"
    }
  }

  public var description: String {
    "Error \(errorCode) calling \(apiName): \(message)"
  }

  public var errorDescription: String? {
    description
  }

  /// Invokes a closure that invokes a Git API call and throws a `GitError` if the closure returns anything other than `GIT_OK`.
  static func check(apiName: String, closure: () -> Int32) throws {
    let result = closure()
    guard result == GIT_OK.rawValue else {
      throw GitError(errorCode: result, apiName: apiName)
    }
  }

  static func checkAndReturn(apiName: String, closure: (inout OpaquePointer?) -> Int32) throws -> OpaquePointer {
    var pointer: OpaquePointer?
    let result = closure(&pointer)
    guard let returnedPointer = pointer, result == GIT_OK.rawValue else {
      throw GitError(errorCode: result, apiName: apiName)
    }
    return returnedPointer
  }

  static func checkAndReturnOID(apiName: String, closure: (inout git_oid) -> Int32) throws -> ObjectID {
    var oid = git_oid()
    let result = closure(&oid)
    guard result == GIT_OK.rawValue else {
      throw GitError(errorCode: result, apiName: apiName)
    }
    return ObjectID(oid)
  }
}
