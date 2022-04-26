import AsyncSwiftGit
import XCTest

final class RepositoryTests: XCTestCase {
  func testCreateBareRepository() throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testCreateBareRepository.git")
    _ = try Repository(createAt: location, bare: true)
  }

  func testCreateNonBareRepository() throws {
    let location = FileManager.default.temporaryDirectory.appendingPathComponent("testCreateNonBareRepository.git")
    _ = try Repository(createAt: location, bare: false)
  }
}
