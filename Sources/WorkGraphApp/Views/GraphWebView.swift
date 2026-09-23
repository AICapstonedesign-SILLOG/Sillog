import AppKit
import SwiftUI
import WebKit
import WorkGraphCore

/// 옵시디언식 그래프 뷰. 화면은 번들된 HTML/JS(force-graph)이고, Swift 는 데이터만 넣어준다.
struct GraphWebView: NSViewRepresentable {
    @EnvironmentObject private var state: AppState
    let version: Int

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "wg")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")              // 로딩 중 흰 화면 방지
        context.coordinator.webView = webView
        if let directory = Self.graphDirectory() {
            webView.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
        } else {
            webView.loadHTMLString("<body style='background:#1e1e1e;color:#ddd;font:14px -apple-system;padding:40px'>그래프 화면 리소스를 찾지 못했습니다.</body>", baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.pushedVersion != version { context.coordinator.push(version: version) }
    }

    /// .app 번들이면 Contents/Resources/graph, `swift run` 이면 SwiftPM 리소스 번들.
    static func graphDirectory() -> URL? {
        if let bundled = Bundle.main.url(forResource: "graph", withExtension: nil) { return bundled }
        return Bundle.module.url(forResource: "graph", withExtension: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let state: AppState
        weak var webView: WKWebView?
        var pushedVersion = -1
        private var ready = false

        init(state: AppState) { self.state = state }

        func push(version: Int) {
            guard ready, let webView else { return }
            pushedVersion = version
            let json = MainActor.assumeIsolated { state.graphJSON() }
            webView.callAsyncJavaScript("window.WG.setGraph(JSON.parse(data))", arguments: ["data": json], in: nil, in: .page, completionHandler: nil)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                ready = true
                push(version: MainActor.assumeIsolated { state.graphVersion })
            case "log":
                if let message = body["message"] as? String { AppLog.write(message) }
            case "resume":
                guard let label = body["label"] as? String, let key = body["key"] as? String else { return }
                Task { @MainActor in self.state.prepareResume(label: label, key: key) }
            case "runBatch":
                Task { @MainActor in await self.state.runBatch(force: true) }
            case "open":
                guard let uri = body["uri"] as? String else { return }
                if uri.hasPrefix("file:") {
                    var path = String(uri.dropFirst("file:".count))
                    if path.hasPrefix("~") { path = NSHomeDirectory() + path.dropFirst(1) }
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                } else if let url = URL(string: uri), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                }
            default:
                break
            }
        }
    }
}
