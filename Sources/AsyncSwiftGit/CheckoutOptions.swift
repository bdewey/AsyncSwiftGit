import Clibgit2
import Foundation

//public typealias ProgressCallback = (String, Int, Int) -> Void

extension git_checkout_strategy_t: OptionSet {}

/// Factory methods to create `git_checkout_options`
struct CheckoutOptions {
  var checkoutStrategy = GIT_CHECKOUT_SAFE

  func withOptions<T>(_ block: (inout git_checkout_options) throws -> T) rethrows -> T {
    var options = git_checkout_options()
    git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
    options.checkout_strategy = checkoutStrategy.rawValue
    return try block(&options)
  }
}
