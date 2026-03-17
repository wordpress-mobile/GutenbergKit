import SwiftUI
import GutenbergKitHTTP

struct MediaProxyServerView: View {

    @State private var server: HTTPServer?
    @State private var logs: [LogEntry] = []
    @State private var localAddress: String = ""
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var logContinuation: AsyncStream<LogEntry>.Continuation?
    @State private var externallyAccessible = true
    @State private var speedTestResults: [SpeedTestResult] = []
    @State private var isRunningSpeedTest = false

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let method: String
        let target: String
        let requestBodySize: Int
    }

    struct SpeedTestResult: Identifiable {
        let id = UUID()
        let size: Int
        let duration: TimeInterval
        var throughput: Double { Double(size) / duration }
    }

    private var isRunning: Bool { server != nil }

    var body: some View {
        List {
            Section {
                LabeledContent("Address") {
                    if let server {
                        Text(verbatim: "\(localAddress):\(server.port)")
                            .monospaced()
                            .textSelection(.enabled)
                    } else {
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Externally Accessible", isOn: $externallyAccessible)
                    .disabled(!isRunning)
                    .onChange(of: externallyAccessible) {
                        Task {
                            stopServer()
                            await startServer()
                        }
                    }

                if isRunning {
                    Button("Stop Server", role: .destructive) {
                        stopServer()
                    }
                } else if !isStarting {
                    Button("Start Server") {
                        Task { await startServer() }
                    }
                }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section("Speed Test") {
                if isRunning {
                    Button(isRunningSpeedTest ? "Running..." : "Run Speed Test") {
                        Task { await runSpeedTest() }
                    }
                    .disabled(isRunningSpeedTest)
                }
                if !speedTestResults.isEmpty {
                    HStack {
                        Text("Size")
                            .frame(width: 80, alignment: .leading)
                        Text("Time")
                            .frame(width: 70, alignment: .trailing)
                        Spacer()
                        Text("Throughput")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                ForEach(speedTestResults) { result in
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(result.size), countStyle: .binary))
                            .frame(width: 80, alignment: .leading)
                        Text(String(format: "%.0f ms", result.duration * 1000))
                            .frame(width: 70, alignment: .trailing)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(result.throughput), countStyle: .binary) + "/s")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }

            Section("Request Log") {
                if logs.isEmpty {
                    ContentUnavailableView("No Requests", systemImage: "network")
                } else {
                    ForEach(logs) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.method) \(entry.target)")
                                .font(.system(.caption, design: .monospaced))
                            HStack {
                                Text(entry.timestamp, style: .time)
                                Text(verbatim: "·")
                                Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(entry.requestBodySize), countStyle: .binary))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Media Proxy Server")
        .task {
            await startServer()
        }
        .onDisappear {
            stopServer()
        }
    }

    private func startServer() async {
        guard server == nil else { return }
        isStarting = true
        errorMessage = nil

        let (stream, continuation) = AsyncStream.makeStream(of: LogEntry.self)
        self.logContinuation = continuation

        do {
            // Authentication is disabled for this demo app — it is never shipped to
            // end users. Production code should always set requiresAuthentication: true.
            let s = try await HTTPServer.start(
                name: "media-proxy-demo",
                port: 8080,
                listenOnAllInterfaces: externallyAccessible,
                requiresAuthentication: false
            ) { request in
                let entry = LogEntry(
                    timestamp: Date(),
                    method: request.parsed.method,
                    target: request.parsed.target,
                    requestBodySize: request.parsed.body?.count ?? 0
                )
                continuation.yield(entry)
                return HTTPResponse(status: 200, body: Data("OK\n".utf8))
            }
            localAddress = externallyAccessible
                ? (Self.getLocalIPAddress() ?? "unknown")
                : "127.0.0.1"
            server = s
            isStarting = false

            // Note: logs grows without bound. This is acceptable for a demo app;
            // a production UI should cap the list or use a ring buffer.
            for await entry in stream {
                logs.insert(entry, at: 0)
            }
        } catch {
            errorMessage = error.localizedDescription
            isStarting = false
        }
    }

    private func runSpeedTest() async {
        guard let server else { return }
        isRunningSpeedTest = true
        speedTestResults = []

        let sizes = [128 * 1024, 512 * 1024, 1024 * 1024, 5 * 1024 * 1024, 10 * 1024 * 1024]
        // 127.0.0.1 is intentional — the speed test is a local self-benchmark,
        // not a device-to-device test. The server's externallyAccessible toggle
        // controls whether remote clients can connect.
        let url = URL(string: "http://127.0.0.1:\(server.port)/speed-test")!

        for size in sizes {
            let payload = Data(repeating: 0x42, count: size)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = payload

            let start = ContinuousClock.now
            _ = try? await URLSession.shared.data(for: request)
            let elapsed = start.duration(to: .now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

            speedTestResults.append(SpeedTestResult(size: size, duration: seconds))
        }

        isRunningSpeedTest = false
    }

    private func stopServer() {
        logContinuation?.finish()
        logContinuation = nil
        server?.stop()
        server = nil
    }

    static func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING) else { continue }
            guard addr.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                ptr.pointee.ifa_addr,
                socklen_t(addr.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            ) == 0 {
                return String(cString: hostname)
            }
        }
        return nil
    }
}
