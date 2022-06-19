// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE file

import Foundation

/// Thrown when two branches conflict.
public struct ConflictError: Error, LocalizedError {
  public let conflictingPaths: [String]

  public var errorDescription: String? {
    conflictingPaths.count == 1
      ? "Conflicting file: \(conflictingPaths[0])"
      : "Conflicting files: \(conflictingPaths.joined(separator: ", "))"
  }
}
