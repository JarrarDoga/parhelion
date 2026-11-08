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

/// Calls `body` with ranges that together cover `0..<count`, on several
/// threads when there is enough work for them. `body` must write only the
/// parts of its output that its range names.
///
/// Work smaller than `minimum` items in each of two ranges runs on the
/// calling thread: starting threads costs more than it saves there.
package func forEachRange(
    of count: Int, minimum: Int, _ body: @Sendable (Range<Int>) -> Void
) {
    let threads = min(ProcessInfo.processInfo.activeProcessorCount, 4, count / max(minimum, 1))
    guard threads > 1 else {
        body(0..<count)
        return
    }
    let chunk = (count + threads - 1) / threads
    DispatchQueue.concurrentPerform(iterations: threads) { index in
        let start = index * chunk
        let end = min(start + chunk, count)
        if start < end { body(start..<end) }
    }
}
