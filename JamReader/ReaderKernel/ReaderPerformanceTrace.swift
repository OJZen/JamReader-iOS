import Foundation
import os

enum ReaderPerformanceTrace {
#if DEBUG
    private static let enabled = ProcessInfo.processInfo.environment["JAM_READER_TRACE"] == "1"
#else
    private static let enabled = false
#endif

    private static let launchUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else {
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        let elapsedMilliseconds = milliseconds(from: now - launchUptimeNanoseconds)
        let threadName = Thread.isMainThread ? "main" : "bg"
        let traceMessage = AppLogSanitizer.truncated(message())
        AppLog.reader.debug(
            "Reader trace elapsedMs=\(format(milliseconds: elapsedMilliseconds), privacy: .public) thread=\(threadName, privacy: .public) message=\(traceMessage, privacy: .public)"
        )
    }

    static func measure<T>(_ label: String, _ work: () -> T) -> T {
        guard enabled else {
            return work()
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        log("\(label) took \(format(nanoseconds: DispatchTime.now().uptimeNanoseconds - start))ms")
        return result
    }

    static func formatInterval(since startUptimeNanoseconds: UInt64?) -> String {
        guard let startUptimeNanoseconds else {
            return "n/a"
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - startUptimeNanoseconds
        return format(nanoseconds: elapsed)
    }

    static func milliseconds(from nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }

    static func format(nanoseconds: UInt64) -> String {
        format(milliseconds: milliseconds(from: nanoseconds))
    }

    static func format(milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}
