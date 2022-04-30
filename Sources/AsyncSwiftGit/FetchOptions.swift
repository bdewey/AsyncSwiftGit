import Clibgit2
import Foundation


struct FetchOptions {
  var progressCallback: Repository.CloneProgressBlock?

  func makeOptions() -> git_fetch_options {
    var options = git_fetch_options()
    git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION))
    if let progressCallback = progressCallback {
      options.callbacks.transfer_progress = fetchProgress

      // TODO: Who's going to free this?
      let buffer = UnsafeMutablePointer<Repository.CloneProgressBlock>.allocate(capacity: 1)
      buffer.initialize(to: progressCallback)
      options.callbacks.payload = UnsafeMutableRawPointer(buffer)
    }
    return options
  }
}

func fetchProgress(progressPointer: UnsafePointer<git_indexer_progress>?, payload: UnsafeMutableRawPointer?) -> Int32 {
  guard let payload = payload else {
    return 0
  }

  let buffer = payload.assumingMemoryBound(to: Repository.CloneProgressBlock.self)
  if let progress = progressPointer?.pointee {
    let progressPercentage = (Double(progress.received_objects) + Double(progress.indexed_objects)) / (2 * Double(progress.total_objects))
    buffer.pointee(progressPercentage)
  }
  return 0
}
