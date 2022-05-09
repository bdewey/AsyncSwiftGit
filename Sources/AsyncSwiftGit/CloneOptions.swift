import Clibgit2
import Foundation

struct CloneOptions {
  var fetchOptions: FetchOptions?

  func withOptions<T>(closure: (git_clone_options) throws -> T) rethrows -> T {
    var options = git_clone_options()
    git_clone_options_init(&options, UInt32(GIT_CLONE_OPTIONS_VERSION))
    if let fetchOptions = fetchOptions {
      return try fetchOptions.withOptions { fetchOptions in
        options.fetch_opts = fetchOptions
        return try closure(options)
      }
    } else {
      return try closure(options)
    }
  }
}
