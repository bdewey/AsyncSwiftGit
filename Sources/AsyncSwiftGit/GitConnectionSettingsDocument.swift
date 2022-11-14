// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Foundation
import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
  /// A `UTType` for a document containing a ``SerializedGitConnectionSettings`` struct.
  static let gitConnectionSettings = UTType(exportedAs: "org.brians-brain.GitConnectionSettings")
}

/// A `FileDocument` for reading and writing ``SerializedGitConnectionSettings`` structs.
public struct GitConnectionSettingsDocument: FileDocument {
  public init(settings: SerializedGitConnectionSettings = .plaintext(settings: GitConnectionSettings())) {
    self.settings = settings
  }

  public var settings: SerializedGitConnectionSettings

  public static var readableContentTypes: [UTType] = [.gitConnectionSettings]

  public init(configuration: ReadConfiguration) throws {
    guard
      configuration.file.isRegularFile,
      let data = configuration.file.regularFileContents
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.settings = try JSONDecoder().decode(SerializedGitConnectionSettings.self, from: data)
  }

  public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(settings)
    return FileWrapper(regularFileWithContents: data)
  }
}
