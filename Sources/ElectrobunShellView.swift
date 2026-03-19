import AppKit
import SwiftUI
import WebKit

struct ElectrobunShellView: View {
    @ObservedObject var tabManager: TabManager
    @State private var shellWidth: CGFloat = 430

    private var bgColor: Color { Color(nsColor: GhosttyManager.shared.backgroundColor) }

    var body: some View {
        HStack(spacing: 0) {
            ElectrobunSidebarWebView(tabManager: tabManager)
                .frame(width: shellWidth)

            VerticalResizeDivider(width: $shellWidth, minWidth: 320, maxWidth: 620)

            SplitDropTargetView(tabManager: tabManager) {
                TerminalContainerView(tabManager: tabManager)
            }
        }
        .background(bgColor)
    }
}

struct ElectrobunSidebarWebView: NSViewRepresentable {
    @ObservedObject var tabManager: TabManager

    func makeCoordinator() -> Coordinator {
        Coordinator(tabManager: tabManager)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageHandlerName)
        controller.addUserScript(WKUserScript(source: Coordinator.bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.attach(webView: webView)
        context.coordinator.loadInterfaceIfNeeded()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(tabManager: tabManager)
        if webView.url == nil {
            context.coordinator.loadInterfaceIfNeeded()
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageHandlerName)
        coordinator.detach()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageHandlerName = "termoBridge"
        static let bootstrapScript = #"""
        (() => {
          if (window.__TERMO_BRIDGE__) return;

          const pending = new Map();
          const listeners = new Set();

          window.__TERMO_NATIVE_DELIVER__ = (json) => {
            const payload = JSON.parse(json);
            if (payload?.id && pending.has(payload.id)) {
              pending.get(payload.id)(payload);
              pending.delete(payload.id);
            }
            return true;
          };

          window.__TERMO_NATIVE_EVENT__ = (json) => {
            const payload = JSON.parse(json);
            listeners.forEach((listener) => {
              try {
                listener(payload);
              } catch (error) {
                console.error("termo bridge listener failed", error);
              }
            });
            return true;
          };

          window.__TERMO_BRIDGE__ = {
            invoke(request) {
              const id = request.id || (globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`);
              const message = { ...request, id };
              return new Promise((resolve) => {
                pending.set(id, resolve);
                window.webkit.messageHandlers.termoBridge.postMessage(JSON.stringify(message));
              });
            },
            subscribe(listener) {
              listeners.add(listener);
              return () => listeners.delete(listener);
            },
          };
        })();
        """#

        private weak var webView: WKWebView?
        private var listenerId: UUID?
        private weak var tabManager: TabManager?
        private var hasLoadedInterface = false

        init(tabManager: TabManager) {
            self.tabManager = tabManager
            super.init()
        }

        func attach(webView: WKWebView) {
            self.webView = webView
            subscribeToBridge()
        }

        func detach() {
            if let listenerId {
                BridgeController.shared.removeListener(listenerId)
            }
            listenerId = nil
            webView = nil
        }

        func update(tabManager: TabManager) {
            guard self.tabManager !== tabManager else { return }
            self.tabManager = tabManager

            if let listenerId {
                BridgeController.shared.removeListener(listenerId)
            }
            listenerId = nil
            subscribeToBridge()
        }

        func loadInterfaceIfNeeded() {
            guard !hasLoadedInterface, let webView else { return }
            hasLoadedInterface = true

            if let sidebar = Bundle.main.url(forResource: "sidebar", withExtension: "html")
                ?? Bundle.main.url(forResource: "sidebar", withExtension: "html", subdirectory: "Resources") {
                webView.loadFileURL(sidebar, allowingReadAccessTo: sidebar.deletingLastPathComponent())
                return
            }

            if let bundledIndex = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "webui")
                ?? Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")
                ?? Bundle.main.url(forResource: "index", withExtension: "html") {
                webView.loadFileURL(bundledIndex, allowingReadAccessTo: bundledIndex.deletingLastPathComponent())
                return
            }

            if let override = ProcessInfo.processInfo.environment["TERMO_WEB_UI_URL"],
               let overrideURL = URL(string: override) {
                webView.load(URLRequest(url: overrideURL))
                return
            }

            if let repoIndex = Self.repoDistIndexURL() {
                webView.loadFileURL(repoIndex, allowingReadAccessTo: repoIndex.deletingLastPathComponent())
                return
            }

            if let devURL = URL(string: "http://127.0.0.1:5173") {
                webView.load(URLRequest(url: devURL))
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName,
                  let tabManager,
                  let body = message.body as? String else { return }

            let response = BridgeController.shared.handle(json: body, for: tabManager)
            deliver(response: response)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let tabManager else { return }
            let initialPayload = BridgeController.shared.handle(BridgeRequest(id: "bootstrap", method: .getState), for: tabManager)
            if let response = try? JSONEncoder().encode(initialPayload),
               let json = String(data: response, encoding: .utf8) {
                deliver(response: json)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showFailure(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showFailure(error.localizedDescription)
        }

        private func subscribeToBridge() {
            guard let tabManager else { return }
            listenerId = BridgeController.shared.addListener(for: tabManager) { [weak self] payload in
                self?.deliver(event: payload)
            }
        }

        private func deliver(response: String) {
            evaluate(function: "window.__TERMO_NATIVE_DELIVER__", json: response)
        }

        private func deliver(event: String) {
            evaluate(function: "window.__TERMO_NATIVE_EVENT__", json: event)
        }

        private func evaluate(function: String, json: String) {
            guard let webView, let quoted = Self.javaScriptStringLiteral(json) else { return }
            webView.evaluateJavaScript("\(function)(\(quoted));", completionHandler: nil)
        }

        private func showFailure(_ message: String) {
            guard let webView, let html = failureHTML(message) else { return }
            webView.loadHTMLString(html, baseURL: nil)
        }

        private func failureHTML(_ message: String) -> String? {
            let escaped = message
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return """
            <!doctype html>
            <html>
              <body style=\"margin:0;padding:18px;background:#10161d;color:#f6f2e9;font:12px -apple-system, BlinkMacSystemFont, sans-serif;\">
                <div style=\"opacity:.7;text-transform:uppercase;letter-spacing:.12em;font-size:10px;margin-bottom:10px;\">Termo Webview Error</div>
                <div>\(escaped)</div>
              </body>
            </html>
            """
        }

        private static func javaScriptStringLiteral(_ string: String) -> String? {
            guard let data = try? JSONEncoder().encode(string),
                  let encoded = String(data: data, encoding: .utf8) else { return nil }
            return encoded
        }

        private static func repoDistIndexURL() -> URL? {
            let sourceURL = URL(fileURLWithPath: #filePath)
            let repoRoot = sourceURL.deletingLastPathComponent().deletingLastPathComponent()
            let indexURL = repoRoot.appendingPathComponent("electrobun/dist/index.html")
            return FileManager.default.fileExists(atPath: indexURL.path) ? indexURL : nil
        }
    }
}
