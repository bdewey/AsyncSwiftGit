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
}
