#if canImport(Dispatch)
import Dispatch
#endif
#if canImport(Foundation)
import Foundation
#endif

/// A value that crosses to other threads whose users promise to touch
/// different parts of it, such as a pointer to rows of pixels each thread
/// writes its own rows of.
package struct Unshared<Value>: @unchecked Sendable {
    package var value: Value

    package init(_ value: Value) {
        self.value = value
    }
}

/// The number of processors the process may use, read once: on Linux,
/// Foundation reads it from the scheduler and the cgroup files each time it
/// is asked, which takes about 20 µs, longer than many of the passes that
/// ask.
private let processorCount = ProcessInfo.processInfo.activeProcessorCount

/// How many parts each thread's share of the work is split into.
private let partsPerThread = 4

/// Calls `body` with ranges that together cover `0..<count`, on several
/// threads when there is enough work for them. `body` must write only the
/// parts of its output that its range names.
///
/// Work smaller than `minimum` items in each of two ranges runs on the
/// calling thread: starting threads costs more than it saves there.
package func forEachRange(
    of count: Int, minimum: Int, _ body: @Sendable (Range<Int>) -> Void
) {
    let threads = min(processorCount, 4, count / max(minimum, 1))
    guard threads > 1 else {
        body(0..<count)
        return
    }
    // More parts than threads, which Dispatch hands to its threads as they
    // come free: when another process holds a core, the other threads take
    // the parts it would have drawn instead of waiting for it.
    let parts = min(threads * partsPerThread, count / max(minimum / 2, 1))
    let chunk = (count + parts - 1) / parts
    DispatchQueue.concurrentPerform(iterations: parts) { index in
        let start = index * chunk
        let end = min(start + chunk, count)
        if start < end { body(start..<end) }
    }
}
