// Copyright © 2022 Brian Dewey. Available under the MIT License, see LICENSE for details.

import Clibgit2
import Foundation

// public typealias ProgressCallback = (String, Int, Int) -> Void

extension git_checkout_strategy_t: OptionSet {}

/// Factory methods to create `git_checkout_options`
final class CheckoutOptions {
  init(checkoutStrategy: git_checkout_strategy_t = GIT_CHECKOUT_SAFE, progressCallback: ((CheckoutProgress) -> Void)? = nil) {
    self.checkoutStrategy = checkoutStrategy
    self.progressCallback = progressCallback
  }

  var checkoutStrategy: git_checkout_strategy_t
  var progressCallback: ((CheckoutProgress) -> Void)?

  func toPointer() -> UnsafeMutableRawPointer {
    Unmanaged.passUnretained(self).toOpaque()
  }

  static func fromPointer(_ pointer: UnsafeMutableRawPointer) -> CheckoutOptions {
    Unmanaged<CheckoutOptions>.fromOpaque(UnsafeRawPointer(pointer)).takeUnretainedValue()
  }

  func withOptions<T>(_ block: (inout git_checkout_options) throws -> T) rethrows -> T {
    var options = git_checkout_options()
    git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
    options.checkout_strategy = checkoutStrategy.rawValue
    if progressCallback != nil {
      options.progress_cb = checkoutProgressCallback
      options.progress_payload = toPointer()
    }
    return try block(&options)
  }
}

public struct CheckoutProgress: CustomStringConvertible {
  public var path: String?
  public var completedSteps: Int
  public var totalSteps: Int

  public init(path: String?, completedSteps: Int, totalSteps: Int) {
    self.path = path
    self.completedSteps = completedSteps
    self.totalSteps = totalSteps
  }

  public var description: String {
    if let path = path {
      return "checkout: \(path) completed steps: \(completedSteps) total steps: \(totalSteps)"
    } else {
      return "started checkout, total steps: \(totalSteps)"
    }
  }
}

private func checkoutProgressCallback(path: UnsafePointer<CChar>?, completedSteps: Int, totalSteps: Int, payload: UnsafeMutableRawPointer?) {
  guard let payload = payload else {
    return
  }
  let checkoutOptions = CheckoutOptions.fromPointer(payload)
  let pathString = path.flatMap { String(cString: $0) }
  checkoutOptions.progressCallback?(CheckoutProgress(path: pathString, completedSteps: completedSteps, totalSteps: totalSteps))
}
