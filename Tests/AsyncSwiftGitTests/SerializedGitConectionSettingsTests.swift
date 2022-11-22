// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import AsyncSwiftGit
import XCTest

final class SerializedGitConectionSettingsTests: XCTestCase {
  let settings = GitConnectionSettings(
    remoteURLString: "https://github.com/bdewey/AsyncSwiftGit",
    username: "bdewey@gmail.com",
    email: "",
    password: "p@ssw0rd",
    isReadOnly: true
  )

  func testPasswordProtectedSerializationIncludesPassword() throws {
    let deserializedSettings = try settings.roundtrip(password: "xyzzy")
    XCTAssertEqual(deserializedSettings, settings)
  }

  func testNormalSerializationDoesNotIncludePassword() throws {
    var expectedDeserializedSettings = settings
    expectedDeserializedSettings.password = ""

    let deserializedSettings = try settings.roundtrip(password: nil)
    XCTAssertEqual(deserializedSettings, expectedDeserializedSettings)
  }
}

extension GitConnectionSettings {
  func roundtrip(password: String?) throws -> GitConnectionSettings {
    let serializedSettings = try serialize(password: password)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let serialiedData = try encoder.encode(serializedSettings)
    print(String(data: serialiedData, encoding: .utf8)!)

    return try serializedSettings.deserialize(password: password)
  }
}
