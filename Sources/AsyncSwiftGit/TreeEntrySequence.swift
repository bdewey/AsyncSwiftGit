import Clibgit2
import Foundation

/// Traverses all of the entries in a `Tree` and all of its children.
///
/// The sequence entries are a tuple of `([String], Entry)`, where the first element is the "path prefix" to this particular entry through the trees in the repository, and the second element is the `Entry` itself.
public struct TreeEntrySequence: AsyncIteratorProtocol, AsyncSequence {
  private let repository: Repository
  private var stack: [NamedIterator<Tree>]

  init(repository: Repository, tree: Tree) {
    self.repository = repository
    self.stack = [.init(collection: tree)]
  }

  public mutating func next() async throws -> ([String], Entry)? {
    guard !Task.isCancelled, !stack.isEmpty else {
      return nil
    }
    var result = stack[stack.count - 1].next()
    while !stack.isEmpty, result == nil {
      stack.removeLast()
      if !stack.isEmpty {
        result = stack[stack.count - 1].next()
      }
    }
    let pathPrefix = stack.map { $0.name }.compactMap { $0 }
    if let result = result, result.type == .tree {
      let tree = try await repository.lookupTree(for: result)
      stack.append(.init(name: result.name, collection: tree))
    }
    if let result = result {
      return (pathPrefix, result)
    } else {
      return nil
    }
  }

  public func makeAsyncIterator() -> TreeEntrySequence {
    self
  }
}

/// Helper that associates a name with an iterator over a collection.
private struct NamedIterator<C: Collection>: IteratorProtocol {
  let name: String?
  var wrappedIterator: C.Iterator

  init(name: String? = nil, collection: C) {
    self.name = name
    self.wrappedIterator = collection.makeIterator()
  }

  mutating func next() -> C.Element? {
    wrappedIterator.next()
  }
}
