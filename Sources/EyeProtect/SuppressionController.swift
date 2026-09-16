import Foundation

/// Decides whether a Break is currently suppressed, and why. Combines In-Call
/// Detection (primary) with the app Allowlist (secondary override). See CONTEXT.md.
struct SuppressionController {
    let calls = CallDetector()
    let frontmost = FrontmostAppMonitor()

    struct Result {
        let suppressed: Bool
        let reason: String?
    }

    func evaluate(detectCalls: Bool, allowlist: [String]) -> Result {
        if detectCalls && calls.inCall {
            return Result(suppressed: true, reason: "in a call")
        }
        if let id = frontmost.frontmostBundleID, allowlist.contains(id) {
            return Result(suppressed: true, reason: "\(frontmost.frontmostName ?? "app") is open")
        }
        return Result(suppressed: false, reason: nil)
    }
}
