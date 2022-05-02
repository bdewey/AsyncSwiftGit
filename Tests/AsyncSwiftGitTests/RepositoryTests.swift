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

  func testBasicClone() async throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testBasicClone")
    defer {
      try? FileManager.default.removeItem(at: location)
    }
    let repository = try await Repository.clone(from: URL(string: "https://github.com/bdewey/jubliant-happiness")!, to: location)
    XCTAssertNotNil(repository.workingDirectoryURL)
    print("Cloned to \(repository.workingDirectoryURL?.absoluteString ?? "nil")")
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
}
