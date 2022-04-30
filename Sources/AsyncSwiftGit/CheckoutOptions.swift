import Clibgit2
import Foundation

public typealias ProgressCallback = (String, Int, Int) -> Void

/// Factory methods to create `git_checkout_options`
struct CheckoutOptions {
  var progressCallback: ProgressCallback?
  var fetchOptions: FetchOptions

  func makeOptions() -> git_checkout_options {
    var options = git_checkout_options()
    git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
    return options
  }
}
