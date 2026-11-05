#if canImport(UIKit)
import UIKit
import WebKit

/// Spike CMM-2752 (throwaway): holds a background-task assertion while the page
/// reports a save in flight, and reports what happens back to the page's log.
@MainActor
final class SpikeS4KeepAlive: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private var tasks: [String: UIBackgroundTaskIdentifier] = [:]
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification] {
            let label = name.rawValue
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report("app \(label)", [
                        "remaining": Self.remaining(),
                        "openTasks": self?.tasks.count ?? 0
                    ])
                }
            })
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let phase = body["phase"] as? String,
              let attemptId = body["attemptId"] as? String else { return }
        if phase == "begin" {
            let task = UIApplication.shared.beginBackgroundTask(withName: "s4-save-\(attemptId)") { [weak self] in
                MainActor.assumeIsolated {
                    self?.report("expired", ["attemptId": attemptId])
                    self?.end(attemptId)
                }
            }
            tasks[attemptId] = task
            report("begin", ["attemptId": attemptId, "task": task.rawValue])
        } else {
            end(attemptId)
        }
    }

    private func end(_ attemptId: String) {
        guard let task = tasks.removeValue(forKey: attemptId) else { return }
        report("end", ["attemptId": attemptId, "remaining": Self.remaining()])
        UIApplication.shared.endBackgroundTask(task)
    }

    private static func remaining() -> String {
        let value = UIApplication.shared.backgroundTimeRemaining
        return value > 1e6 ? "unlimited" : String(format: "%.1f", value)
    }

    private func report(_ message: String, _ data: [String: Any]) {
        var data = data
        data["at"] = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        NSLog("[s4 native] \(message) \(data)")
        guard let json = try? JSONSerialization.data(withJSONObject: data),
              let string = String(data: json, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__s4?.nativeLog?.(\(String(reflecting: message)), \(string))")
    }
}
#endif
