// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import CryptoKit
import Foundation

/// Serialization container for ``GitConnectionSettings``
public enum SerializedGitConnectionSettings: Codable {
  case plaintext(settings: GitConnectionSettings)
  case passwordProtected(data: Data)

  /// True if the receiver needs a password to be deserialized.
  public var needsPassword: Bool {
    switch self {
    case .plaintext: return false
    case .passwordProtected: return true
    }
  }

  public enum Error: Swift.Error {
    /// The serialized settings are password protected, but no password was provided.
    case needsPassword
  }

  /// Deserialize ``GitConnectionSettings`` from the receiver.
  /// - Parameter password: If the receiver is password protected, this must be the password for deserialization.
  /// - Returns: The deserialized settings.
  public func deserialize(password: String? = nil) throws -> GitConnectionSettings {
    switch self {
    case .plaintext(settings: let settings):
      return settings
    case .passwordProtected(data: let data):
      guard let password else {
        throw Error.needsPassword
      }
      let key = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: password.data(using: .utf8)!),
        outputByteCount: 32
      )
      let box = try ChaChaPoly.SealedBox(combined: data)
      let plaintext = try ChaChaPoly.open(box, using: key)
      return try JSONDecoder().decode(GitConnectionSettings.self, from: plaintext)
    }
  }
}

public extension GitConnectionSettings {
  /// Serialize these settings.
  /// - Parameter password: If non-nil, the receiver will be serialized in "pasword-protected" form, which will include the connection password. If nil, the receiver will be in "plain-text" form and the password will be removed.
  /// - Returns: A ``SerializedGitConnectionSettings`` that contains the serialized form of the receiver.
  func serialize(password: String? = nil) throws -> SerializedGitConnectionSettings {
    guard let password else {
      var settingsCopy = self
      settingsCopy.password = ""
      return .plaintext(settings: settingsCopy)
    }
    let key = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: password.data(using: .utf8)!),
      outputByteCount: 32
    )
    let encoder = JSONEncoder()
    encoder.userInfo[.includeConnectionPasswordKey] = true
    let plaintext = try encoder.encode(self)
    let ciphertext = try ChaChaPoly.seal(plaintext, using: key).combined
    return .passwordProtected(data: ciphertext)
  }
}
