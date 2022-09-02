// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

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
    try repository.addRemote("origin", url: URL(string: "https://github.com/bdewey/jubliant-happiness")!)
    let progressStream = repository.fetchProgress(remote: "origin")
    for try await progress in progressStream {
      print("Fetch progress: \(progress)")
    }
    let result = try repository.merge(revisionSpecification: "origin/main", signature: Signature(name: "John Q. Tester", email: "tester@me.com"))
    XCTAssertTrue(result.isFastForward)
    let (ahead, behind) = try repository.commitsAheadBehind(other: "origin/main")
    XCTAssertEqual(ahead, 0)
    XCTAssertEqual(behind, 0)
    let expectedFilePath = repository.workingDirectoryURL!.appendingPathComponent("Package.swift").path
    print("Looking for file at \(expectedFilePath)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFilePath))
  }

  func testCheckoutRemote() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testFetchFastForward")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try Repository(createAt: location, bare: false)
    try repository.addRemote("origin", url: URL(string: "https://github.com/bdewey/jubliant-happiness")!)
    try await repository.fetch(remote: "origin")
    for try await progress in repository.checkoutProgress(referenceShorthand: "origin/main") {
      print(progress)
    }
    try repository.checkNormalState()
    let statusEntries = try repository.statusEntries
    print(statusEntries)
    XCTAssertTrue(statusEntries.isEmpty)
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
    try repository.add("local.txt")
    let commitTime = Date()
    try repository.commit(message: "Local commit", signature: Signature(name: "John Q. Tester", email: "tester@me.com", time: commitTime))
    let timeFromRepo = try repository.head!.commit.commitTime
    XCTAssertEqual(commitTime.timeIntervalSince1970, timeFromRepo.timeIntervalSince1970, accuracy: 1)
    try repository.addRemote("origin", url: URL(string: "https://github.com/bdewey/jubliant-happiness")!)
    try await repository.fetch(remote: "origin")
    var (ahead, behind) = try repository.commitsAheadBehind(other: "origin/main")
    XCTAssertEqual(ahead, 1)
    XCTAssertEqual(behind, 1)
    let result = try repository.merge(revisionSpecification: "origin/main", signature: Signature(name: "John Q. Tester", email: "tester@me.com"))
    XCTAssertTrue(result.isMerge)
    try repository.checkNormalState()
    (ahead, behind) = try repository.commitsAheadBehind(other: "origin/main")
    XCTAssertEqual(ahead, 2)
    XCTAssertEqual(behind, 0)
    let expectedFilePath = repository.workingDirectoryURL!.appendingPathComponent("Package.swift").path
    print("Looking for file at \(expectedFilePath)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFilePath))
    try "Another file\n".write(to: repository.workingDirectoryURL!.appendingPathComponent("another.txt"), atomically: true, encoding: .utf8)
    try repository.add("*")
    try repository.commit(message: "Moving ahead of remote", signature: Signature(name: "John Q. Tester", email: "tester@me.com"))
    (ahead, behind) = try repository.commitsAheadBehind(other: "origin/main")
    XCTAssertEqual(ahead, 3)
    XCTAssertEqual(behind, 0)
  }

  func testCloneWithProgress() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testBasicClone")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    var repository: Repository!
    for try await progress in Repository.cloneProgress(from: URL(string: "https://github.com/bdewey/SpacedRepetitionScheduler")!, to: location) {
      switch progress {
      case .progress(let progress):
        print("Clone progress: \(progress)")
      case .completed(let repo):
        repository = repo
      }
    }
    XCTAssertNotNil(repository.workingDirectoryURL)
    print("Cloned to \(repository.workingDirectoryURL?.absoluteString ?? "nil")")
    var commitCount = 0
    for try await commit in repository.log(revspec: "HEAD") {
      print("\(commit)")
      commitCount += 1
    }
    XCTAssertEqual(commitCount, 9)
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
    let tree = try repository.headTree
    for try await qualfiedEntry in repository.treeWalk(tree: tree) {
      print(qualfiedEntry)
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
    let entries = repository.treeWalk()
    guard let gitIgnoreEntry = try await entries.first(where: { $0.name == ".gitignore" }) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let data = try repository.data(for: gitIgnoreEntry.objectID)
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
    try repository.add()
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
    try repository.add()
    let firstCommitOID = try repository.commit(message: "First commit", signature: signature)
    print("First commit: \(firstCommitOID)")
    try "Hello, world\n".write(to: repository.workingDirectoryURL!.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
    try repository.add()
    let secondCommitOID = try repository.commit(message: "Second commit", signature: signature)
    print("Second commit: \(secondCommitOID)")

    let firstDiff = try repository.diff(nil, try repository.lookupCommit(for: firstCommitOID).tree)
    XCTAssertEqual(firstDiff.count, 1)
  }

  func testCommitsAheadBehind() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testCommitsAheadBehind")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let clientURL = location.appendingPathComponent("client")
    try? FileManager.default.createDirectory(at: clientURL, withIntermediateDirectories: true)
    let serverURL = location.appendingPathComponent("server")
    try? FileManager.default.createDirectory(at: serverURL, withIntermediateDirectories: true)
    let clientRepository = try Repository(createAt: clientURL)
    let serverRepository = try Repository(createAt: serverURL)
    try clientRepository.addRemote("origin", url: serverURL)
    try await clientRepository.fetch(remote: "origin")
    let initialTuple = try clientRepository.commitsAheadBehind(other: "origin/main")
    XCTAssertEqual(initialTuple.ahead, 0)
    XCTAssertEqual(initialTuple.behind, 0)

    // Commit some stuff to `server` and fetch it
    try "test1\n".write(to: serverURL.appendingPathComponent("test1.txt"), atomically: true, encoding: .utf8)
    try serverRepository.add()
    try serverRepository.commit(message: "test1", signature: Signature(name: "bkd", email: "noone@foo.com", time: Date()))

    try "test2\n".write(to: serverURL.appendingPathComponent("test2.txt"), atomically: true, encoding: .utf8)
    try serverRepository.add()
    try serverRepository.commit(message: "test2", signature: Signature(name: "bkd", email: "noone@foo.com", time: Date()))

    try await clientRepository.fetch(remote: "origin")
    let fetchedTuple = try clientRepository.commitsAheadBehind(other: "origin/main")
    XCTAssertEqual(fetchedTuple.ahead, 0)
    XCTAssertEqual(fetchedTuple.behind, 2)

    let mergeResult = try clientRepository.merge(revisionSpecification: "origin/main", signature: Signature(name: "bkd", email: "noone@foo.com", time: Date()))
    XCTAssertTrue(mergeResult.isFastForward)

    let nothingOnServer = try clientRepository.commitsAheadBehind(other: "fake")
    XCTAssertEqual(nothingOnServer.ahead, 2)
    XCTAssertEqual(nothingOnServer.behind, 0)
  }
}
