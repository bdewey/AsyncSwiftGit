// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Foundation

/// Type for all of the settings required to connect to a remote ``Repository``.
///
/// This type is designed for use in UI components that let people fill out sync settings -- it is possible to have invalid settings (e.g., missing required values or invalid connection strings).
/// You can determine if the contents of this type are valid for synchronization by using ``isValid``.
///
/// If the type is valid, you can get ``Credentials`` for connection and a ``Signature`` for authoring commits.
public struct GitConnectionSettings: Codable, Equatable {
  public enum AuthenticationType: String, Codable {
    case usernamePassword = "https" // There are serialized versions of settings that called this "https"
    case ssh
    case none
  }

  public struct SSHKeyPair: Codable, Equatable {
    public var publicKey = ""
    public var privateKey = ""

    public init(publicKey: String = "", privateKey: String = "") {
      self.publicKey = publicKey
      self.privateKey = privateKey
    }

    public var isValid: Bool {
      !publicKey.isEmpty && !privateKey.isEmpty
    }
  }

  public init(remoteURLString: String = "", username: String = "", email: String = "", password: String = "", isReadOnly: Bool = false) {
    self.remoteURLString = remoteURLString
    self.username = username
    self.email = email
    self.password = password
    self.isReadOnly = isReadOnly
  }

  /// How we are supposed to connect to the server
  public var connectionType = AuthenticationType.usernamePassword

  /// The `git` remote URL containing the master copy of the repository.
  public var remoteURLString = ""

  /// The username to use for recording all transactions.
  public var username = ""

  /// The email to use for recording all transactions. This will also be used in the "username" field when connecting to ``remoteURL``.
  public var email = ""

  /// If true, we expect to only have read-only credentials. Don't try to push changes and don't allow transaction edits.
  public var isReadOnly = false

  /// The password to use when connecting to the repository. (This is probably a Github Personal Access Token, not a real password.)
  /// Note we have a custom `Codable` conformance to make sure this value isn't persisted
  public var password = ""

  /// If connectionType == .ssh, this will contain the SSH key pair
  public var sshKeyPair = SSHKeyPair()

  private enum CodingKeys: CodingKey {
    case remoteURLString
    case username
    case email
    case isReadOnly
    case connectionType
    case sshKey
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.remoteURLString = try container.decode(String.self, forKey: .remoteURLString)
    self.username = try container.decode(String.self, forKey: .username)
    self.email = try container.decode(String.self, forKey: .email)
    self.isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
    self.connectionType = try container.decode(AuthenticationType.self, forKey: .connectionType)
    self.sshKeyPair = try container.decode(SSHKeyPair.self, forKey: .sshKey)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(remoteURLString, forKey: .remoteURLString)
    try container.encode(username, forKey: .username)
    try container.encode(email, forKey: .email)
    try container.encode(isReadOnly, forKey: .isReadOnly)
    try container.encode(connectionType, forKey: .connectionType)
    try container.encode(sshKeyPair, forKey: .sshKey)
  }

  public var keychainIdentifier: String {
    [remoteURLString, email].joined(separator: "__")
  }

  /// True if all required settings properties are filled in
  public var isValid: Bool {
    isConnectionInformationValid && isPersonalInformationValid
  }

  private var isPersonalInformationValid: Bool {
    // EITHER we are read-only (and don't need username / email) OR we need both username & email.
    isReadOnly || (!username.isEmpty && !email.isEmpty)
  }

  private var isConnectionInformationValid: Bool {
    switch connectionType {
    case .usernamePassword:
      return isRemoteURLValid && !email.isEmpty && (isReadOnly || !password.isEmpty)
    case .ssh:
      return sshKeyPair.isValid && !password.isEmpty
    case .none:
      return true
    }
  }

  public var credentials: Credentials {
    switch connectionType {
    case .usernamePassword:
      return .plaintext(username: username, password: password)
    case .ssh:
      return .sshMemory(username: "git", publicKey: sshKeyPair.publicKey, privateKey: sshKeyPair.privateKey, passphrase: password)
    case .none:
      return .default
    }
  }

  public func makeSignature(time: Date, timeZone: TimeZone = .current) throws -> Signature {
    try Signature(name: username, email: email, time: time, timeZone: timeZone)
  }

  public var isRemoteURLValid: Bool {
    if connectionType == .ssh {
      // I don't validate SSH connection strings right now
      return true
    }
    guard let components = URLComponents(string: remoteURLString) else {
      return false
    }
    let validScheme = components.scheme?.lowercased() == "http" || components.scheme?.lowercased() == "https"
    let emptyHost = components.host?.isEmpty ?? true
    return validScheme && !emptyHost
  }
}
