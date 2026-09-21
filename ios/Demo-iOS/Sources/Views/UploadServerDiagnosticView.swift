import SwiftUI
import UIKit
import Network
import OSLog
import GutenbergKitHTTP

/// Diagnostic for the "backgrounded upload server loses its socket" behaviour.
///
/// The editor's media upload server is a loopback ``HTTPServer``. When the device becomes
/// eligible for idle sleep — e.g. the phone is locked while unplugged and left to idle —
/// iOS reclaims the listening socket out from under a suspended app: connections are then
/// refused even though `NWListener` still reports `.ready`, so nothing is logged and the
/// editor returns advertising a dead port. `EditorViewController` recovers by re-checking
/// the port on `willEnterForeground` and restarting the server if it stopped answering.
///
/// This screen exercises the same shape with a standalone ``HTTPServer`` so the behaviour
/// and the recovery can be validated on a device:
///
/// - **Live monitor** — start the server, then lock the phone (unplugged, left to idle) and
///   reopen. The monitor reports whether the socket was reclaimed while away, and if so
///   restarts it and confirms it answers again.
/// - **Self-test** — stops the server to stand in for the OS reclaiming the socket, confirms
///   it stops answering, restarts it, and confirms it answers on the new port. This proves
///   the recovery path deterministically, without needing to lock the phone.
@MainActor
final class UploadServerDiagnostic: ObservableObject {
    enum Reachability { case unknown, reachable, unreachable }

    struct Outcome: Identifiable {
        let id = UUID()
        let text: String
        let passed: Bool
    }

    @Published private(set) var reachability: Reachability = .unknown
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var power = ""
    @Published private(set) var awaySeconds = ""
    @Published private(set) var events: [String] = []
    @Published private(set) var outcomes: [Outcome] = []
    @Published private(set) var isRunningSelfTest = false
    @Published private(set) var uploadSimulationActive = false
    @Published private(set) var backgroundTimeRemaining = ""

    private var server: HTTPServer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var backgroundedAt: Date?
    private var uploadTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Lifecycle

    func onAppear() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        Task { await startServer(reason: "initial start") }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.backgroundedAt = Date() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleForeground() }
        })
    }

    func onDisappear() {
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        endUploadSimulation()
        server?.stop()
        server = nil
    }

    // MARK: - Active-upload simulation (background-task assertion)

    /// Holds a `UIApplication` background-task assertion — the same primitive the editor's
    /// upload path holds while relaying a media upload. With it held, locking the phone keeps
    /// the app running for the system's grace period (~30s) instead of suspending it, so a
    /// short upload finishes and the loopback socket survives a brief lock.
    func toggleUploadSimulation() {
        uploadSimulationActive ? endUploadSimulation() : beginUploadSimulation()
    }

    private func beginUploadSimulation() {
        uploadTask = UIApplication.shared.beginBackgroundTask(withName: "diagnostic-upload") { [weak self] in
            Task { @MainActor in self?.endUploadSimulation() }
        }
        guard uploadTask != .invalid else {
            log("Could not start a background-task assertion.")
            return
        }
        uploadSimulationActive = true
        log("Simulated upload started — holding a background-task assertion. Lock the phone now; the app should keep running (~30s) and the socket should stay ALIVE.")
    }

    private func endUploadSimulation() {
        guard uploadSimulationActive else { return }
        if uploadTask != .invalid {
            UIApplication.shared.endBackgroundTask(uploadTask)
            uploadTask = .invalid
        }
        uploadSimulationActive = false
        backgroundTimeRemaining = ""
        log("Simulated upload ended — assertion released.")
    }

    // MARK: - Live monitor

    /// Runs when the app returns to the foreground — the same moment the editor's fix runs.
    private func handleForeground() async {
        let away = backgroundedAt.map { Int(Date().timeIntervalSince($0)) }
        let awayText = away.map { "\($0)s" } ?? "?"
        // Freeze the away time now and stop the running counter — the timer is suspended
        // while backgrounded, so leaving `backgroundedAt` set would make it climb in the
        // foreground.
        awaySeconds = away != nil ? awayText : awaySeconds
        backgroundedAt = nil
        guard let server else { return }

        if await isAnswering(port: server.port) {
            log("Returned after \(awayText): still answering — not reclaimed this cycle.")
            return
        }

        log("Returned after \(awayText): port \(server.port) refused — the OS reclaimed the socket while away.")
        await startServer(reason: "recovery after reclamation")
        if let restarted = self.server, await isAnswering(port: restarted.port) {
            record("Reclaimed after \(awayText), recovered on port \(restarted.port)", passed: true)
        } else {
            record("Reclaimed after \(awayText), but recovery failed", passed: false)
        }
    }

    private func refresh() async {
        guard let server else { reachability = .unknown; return }
        reachability = await isAnswering(port: server.port) ? .reachable : .unreachable
        power = powerLine()
        if uploadSimulationActive {
            let remaining = UIApplication.shared.backgroundTimeRemaining
            backgroundTimeRemaining = remaining > 1_000_000 ? "∞ (foreground)" : "\(Int(remaining))s"
        }
    }

    // MARK: - Self-test

    /// Proves the recovery path without waiting for the OS: stop the server (standing in for
    /// the OS reclaiming the socket), confirm it stops answering, restart, confirm it answers.
    func runSelfTest() async {
        guard !isRunningSelfTest else { return }
        isRunningSelfTest = true
        defer { isRunningSelfTest = false }

        if server == nil { await startServer(reason: "self-test start") }
        guard let original = server, await isAnswering(port: original.port) else {
            record("Self-test: server was not answering at the start", passed: false)
            return
        }

        original.stop()
        server = nil
        guard await stoppedAnswering(port: original.port) else {
            record("Self-test: server kept answering after stop", passed: false)
            return
        }
        log("Self-test: server on port \(original.port) stopped answering (stands in for OS reclamation).")

        await startServer(reason: "self-test recovery")
        guard let restarted = server, await isAnswering(port: restarted.port) else {
            record("Self-test: did not recover after restart", passed: false)
            return
        }
        record("Self-test: stopped → restarted → answering on port \(restarted.port)", passed: true)
    }

    // MARK: - Server

    private func startServer(reason: String) async {
        server?.stop()
        do {
            let server = try await HTTPServer.start(name: "upload-diagnostic", requiresAuthentication: false) { _ in
                HTTPResponse(status: 200, body: Data("ok".utf8))
            }
            self.server = server
            self.port = server.port
            log("Server \(reason): listening on port \(server.port).")
        } catch {
            log("Server \(reason): failed to start — \(error).")
        }
    }

    /// A stopped listener can keep answering briefly, because `cancel()` completes on the
    /// listener's own queue. Poll rather than race it.
    private func stoppedAnswering(port: UInt16) async -> Bool {
        for _ in 0..<20 {
            if await !isAnswering(port: port) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    // MARK: - Reachability probe

    /// Sends a real request over `NWConnection` (not a bare connect, which the server would
    /// log as a dropped connection, and not `URLSession`, so App Transport Security can't
    /// decide the outcome). Any response means the socket is still there.
    private func isAnswering(port: UInt16, timeout: Duration = .seconds(2)) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
        let deadline = Task {
            try await Task.sleep(for: timeout)
            connection.cancel()
        }
        defer {
            deadline.cancel()
            connection.cancel()
        }
        return await withCheckedContinuation { continuation in
            let once = OnceFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let request = Data("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: request, completion: .contentProcessed { error in
                        guard error == nil else {
                            if once.claim() { continuation.resume(returning: false) }
                            return
                        }
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, _, error in
                            let answered = error == nil && !(data ?? Data()).isEmpty
                            if once.claim() { continuation.resume(returning: answered) }
                        }
                    })
                case .failed, .cancelled:
                    if once.claim() { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            connection.start(queue: Self.probeQueue)
        }
    }

    private static let probeQueue = DispatchQueue(label: "com.gutenbergkit.demo.upload-diagnostic-probe")

    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    // MARK: - Helpers

    private func powerLine() -> String {
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "plugged in"
        case .unplugged: state = "unplugged"
        default: state = "unknown power"
        }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled ? ", Low Power" : ""
        return "\(state)\(lowPower)"
    }

    private func log(_ line: String) {
        let stamped = "\(Date().formatted(date: .omitted, time: .standard))  \(line)"
        events.insert(stamped, at: 0)
        if events.count > 100 { events.removeLast() }
    }

    private func record(_ text: String, passed: Bool) {
        outcomes.insert(Outcome(text: text, passed: passed), at: 0)
        log((passed ? "PASS — " : "FAIL — ") + text)
    }
}

struct UploadServerDiagnosticView: View {
    @StateObject private var model = UploadServerDiagnostic()

    var body: some View {
        List {
            Section {
                HStack {
                    Circle().fill(statusColor).frame(width: 12, height: 12)
                    Text(statusText).font(.headline)
                    Spacer()
                    Text("port \(model.port)").font(.caption).monospaced().foregroundStyle(.secondary)
                }
                LabeledContent("Power", value: model.power.isEmpty ? "—" : model.power)
                if !model.awaySeconds.isEmpty {
                    LabeledContent("Last time away", value: model.awaySeconds)
                }
            } header: {
                Text("Upload server socket")
            } footer: {
                Text("Lock the phone (unplugged, left to idle) and reopen. If iOS reclaimed the socket, the monitor restarts it and confirms it answers again.")
            }

            Section("Self-test") {
                Button {
                    Task { await model.runSelfTest() }
                } label: {
                    HStack {
                        Text("Run recovery self-test")
                        Spacer()
                        if model.isRunningSelfTest { ProgressView() }
                    }
                }
                .disabled(model.isRunningSelfTest)
            }

            Section {
                Toggle("Simulate an active upload", isOn: Binding(
                    get: { model.uploadSimulationActive },
                    set: { _ in model.toggleUploadSimulation() }
                ))
                if model.uploadSimulationActive, !model.backgroundTimeRemaining.isEmpty {
                    LabeledContent("Background time remaining", value: model.backgroundTimeRemaining)
                }
            } header: {
                Text("Active upload")
            } footer: {
                Text("Holds the same background-task assertion the editor holds while relaying an upload. With it on, lock the phone: the app keeps running for the grace period, so a short upload finishes and the socket survives the brief lock.")
            }

            if !model.outcomes.isEmpty {
                Section("Results") {
                    ForEach(model.outcomes) { outcome in
                        HStack(alignment: .top) {
                            Image(systemName: outcome.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(outcome.passed ? .green : .red)
                            Text(outcome.text).font(.callout)
                        }
                    }
                }
            }

            if !model.events.isEmpty {
                Section("Log") {
                    ForEach(Array(model.events.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Upload Server Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private var statusColor: Color {
        switch model.reachability {
        case .reachable: return .green
        case .unreachable: return .red
        case .unknown: return .gray
        }
    }

    private var statusText: String {
        switch model.reachability {
        case .reachable: return "Answering"
        case .unreachable: return "Not answering"
        case .unknown: return "Starting…"
        }
    }
}
