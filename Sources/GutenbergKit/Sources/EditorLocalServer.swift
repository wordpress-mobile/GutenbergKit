import Embassy
import Foundation

// FIXME: rework
// This is just for the demo and is absolutely NOT production ready. It should
// be replaced with another framework.
final class EditorLocalServer {
    var eventLoop: EventLoop!
    var eventLoopThreadCondition: NSCondition!
    var eventLoopThread: Thread!
    var server: DefaultHTTPServer!

    func run() throws {
        NSLog("\(Date.now.timeIntervalSince1970))): EditorLocalServer.run")

        eventLoop = try SelectorEventLoop(selector: try KqueueSelector())

        server = DefaultHTTPServer(eventLoop: eventLoop, port: EditorConstants.port, app: makeApp())
        try server.start()

        NSLog("\(Date.now.timeIntervalSince1970): EditorLocalServer.didStart")

        eventLoopThreadCondition = NSCondition()
        eventLoopThread = Thread(target: self, selector: #selector(runEventLoop), object: nil)
        eventLoopThread.start()

        NSLog("\(Date.now.timeIntervalSince1970): EditorLocalServer.didStartThread")
    }

    private func makeApp() -> SWSGI {
        { (environment: [String: Any], startResponse: ((String, [(String, String)]) -> Void), sendBody: ((Data) -> Void)) in

            guard let request = HTTPRequest(environment: environment) else {
                return
            }

            NSLog("\(Date.now.timeIntervalSince1970): request: \(request)")

            let path = request.path
            if path.hasPrefix("/\(EditorConstants.gutenbergLocalPath)"), let url = URL(string: path) {
                let resource = url.deletingPathExtension().lastPathComponent
                let subdirectory = url.deletingLastPathComponent().absoluteString

                guard let fileURL = Bundle.module.url(forResource: resource, withExtension: url.pathExtension, subdirectory: subdirectory) else {
                    // TODO: safe error handling
                    fatalError("missing resource: \(path)")
                }

                let data = try! Data(contentsOf: fileURL)

                // TODO: send date
                // TODO: pass proper contnet-type

                let contentTypes = [
                    "js": "text/javascript",
                    "html": "text/html",
                    "css": "text/css"
                ]

                startResponse("200 OK", [
                    ("Content-Length", String(data.count)),
                    ("Content-Type", "\(contentTypes[url.pathExtension]!); charset=utf-8")
                ])
                // TODO: copy these outside of the module?

                sendBody(data)
                sendBody(Data())

                return
            }

            // TODO: throw error
            NSLog("unhandled request: \(request)")

        }
    }


    @objc private func runEventLoop() {
        NSLog("\(Date.now.timeIntervalSince1970): EditorLocalServer.runEventLoop")
        eventLoop.runForever()
        eventLoopThreadCondition.lock()
        eventLoopThreadCondition.signal()
        eventLoopThreadCondition.unlock()
    }
}

enum EditorConstants {
    static let port = 47197
    static let gutenbergLocalPath = "Gutenberg"
}

//"SERVER_NAME": "[::1]",
//"SERVER_PROTOCOL" : "HTTP/1.1",
//"SERVER_PORT" : "53479",
//"REQUEST_METHOD": "GET",
//"SCRIPT_NAME" : "",
//"PATH_INFO" : "/",
//"HTTP_HOST": "[::1]:8889",
//"HTTP_USER_AGENT" : "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36",
//"HTTP_ACCEPT_LANGUAGE" : "en-US,en;q=0.8,zh-TW;q=0.6,zh;q=0.4,zh-CN;q=0.2",
//"HTTP_CONNECTION" : "keep-alive",
//"HTTP_ACCEPT" : "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
//"HTTP_ACCEPT_ENCODING" : "gzip, deflate, sdch",
//"swsgi.version" : "0.1",
//"swsgi.input" : (Function),
//"swsgi.error" : "",
//"swsgi.multiprocess" : false,
//"swsgi.multithread" : false,
//"swsgi.url_scheme" : "http",
//"swsgi.run_once" : false

private struct HTTPRequest {
    let method: String
    let path: String

    init?(environment: [String: Any]) {
        guard let method = environment["REQUEST_METHOD"] as? String,
              let path = environment["PATH_INFO"] as? String else {
            return nil
        }
        self.method = method
        self.path = path
    }
}
