import AsyncSwiftGit
import XCTest

final class RepositoryTests: XCTestCase {
  func testCreateBareRepository() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testCreateBareRepository.git")
    let repository = try Repository(createAt: location, bare: true)
    let url = repository.workingDirectoryURL
    XCTAssertNil(url)
  }

  func testCreateNonBareRepository() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testCreateNonBareRepository.git")
    let repository = try Repository(createAt: location, bare: false)
    let url = repository.workingDirectoryURL
    XCTAssertNotNil(url)
  }

  func testOpenRepository() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testOpenRepository")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    XCTAssertThrowsError(try Repository(openAt: location))
    _ = try Repository(createAt: location, bare: false)
    let openedRepository = try Repository(openAt: location)
    XCTAssertEqual(openedRepository.workingDirectoryURL?.standardizedFileURL, location.standardizedFileURL)
  }

  func testBasicClone() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testBasicClone")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try await Repository.clone(from: URL(string: "https://github.com/bdewey/jubliant-happiness")!, to: location)
    XCTAssertNotNil(repository.workingDirectoryURL)
    print("Cloned to \(repository.workingDirectoryURL?.absoluteString ?? "nil")")
  }

  func testFetchFastForward() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testFetchFastForward")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try Repository(createAt: location, bare: false)
    try await repository.addRemote("origin", url: URL(string: "https://github.com/bdewey/jubliant-happiness")!)
    try await repository.fetch(remote: "origin")
    let result = try await repository.merge(revspec: "origin/main", signature: Signature(name: "John Q. Tester", email: "tester@me.com"))
    XCTAssertTrue(result.isFastForward)
    let expectedFilePath = repository.workingDirectoryURL!.appendingPathComponent("Package.swift").path
    print("Looking for file at \(expectedFilePath)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFilePath))
  }

  func testFetchNonConflictingChanges() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testFetchNonConflictingChanges")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try Repository(createAt: location, bare: false)
    try "Local file\n".write(to: repository.workingDirectoryURL!.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8)
    try await repository.add("local.txt")
    try await repository.commit(message: "Local commit", signature: Signature(name: "John Q. Tester", email: "tester@me.com"))
    try await repository.addRemote("origin", url: URL(string: "https://github.com/bdewey/jubliant-happiness")!)
    try await repository.fetch(remote: "origin")
    let result = try await repository.merge(revspec: "origin/main", signature: Signature(name: "John Q. Tester", email: "tester@me.com"))
    XCTAssertTrue(result.isMerge)
    let expectedFilePath = repository.workingDirectoryURL!.appendingPathComponent("Package.swift").path
    print("Looking for file at \(expectedFilePath)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFilePath))
  }

  func testCloneWithProgress() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testBasicClone")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try await Repository.clone(
      from: URL(string: "https://github.com/bdewey/SpacedRepetitionScheduler")!,
      to: location,
      progress: { print("Clone progress: \($0)") }
    )
    XCTAssertNotNil(repository.workingDirectoryURL)
    print("Cloned to \(repository.workingDirectoryURL?.absoluteString ?? "nil")")
  }

  func testTreeEnumeration() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testTreeEnumeration")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try await Repository.clone(
      from: URL(string: "https://github.com/bdewey/SpacedRepetitionScheduler")!,
      to: location
    )
    let tree = try await repository.headTree
    for try await (path, entry) in await repository.entries(tree: tree) {
      print(entry.description(treePathSegments: path))
    }
  }

  func testGetDataFromEntry() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testGetDataFromEntry")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try await Repository.clone(
      from: URL(string: "https://github.com/bdewey/SpacedRepetitionScheduler")!,
      to: location
    )
    let tree = try await repository.headTree
    let entries = await repository.entries(tree: tree)
    guard let gitIgnoreEntry = try await entries.first(where: { $0.1.name == ".gitignore" }) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let data = try await repository.lookupBlob(for: gitIgnoreEntry.1)
    let string = String(data: data, encoding: .utf8)!
    print(string)
  }

  func testAddContentToRepository() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testAddContentToRepository")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try Repository(createAt: location, bare: false)
    let testText = "This is some sample text.\n"
    try testText.write(to: repository.workingDirectoryURL!.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
    try await repository.add()
    print(repository.workingDirectoryURL!.absoluteString)
  }

  func testSimpleCommits() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testSimpleCommits")
    let signature = try Signature(name: "Brian Dewey", email: "bdewey@gmail.com")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try Repository(createAt: location, bare: false)
    print("Working directory: \(repository.workingDirectoryURL!.standardizedFileURL.path)")
    let testText = "This is some sample text.\n"
    try testText.write(to: repository.workingDirectoryURL!.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
    try await repository.add()
    let firstCommit = try await repository.commit(message: "First commit", signature: signature)
    print("First commit: \(firstCommit)")
    try "Hello, world\n".write(to: repository.workingDirectoryURL!.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
    try await repository.add()
    let secondCommit = try await repository.commit(message: "Second commit", signature: signature)
    print("Second commit: \(secondCommit)")
  }
}
