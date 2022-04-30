import Clibgit2
import Foundation

struct CloneOptions {
  var fetchOptions: FetchOptions?

  func makeOptions() -> git_clone_options {
    var options = git_clone_options()
    git_clone_options_init(&options, UInt32(GIT_CLONE_OPTIONS_VERSION))
    if let fetchOptions = fetchOptions {
      options.fetch_opts = fetchOptions.makeOptions()
    }
    return options
  }
}
