// SPDX-License-Identifier: GPL-3.0-or-later
//
// Hosts the web fixture page (Resources/page.html) in a WKWebView. The page holds the three
// web controls; selection runs as page script, and the page reports copy and paste back
// through the `fixture` script message handler.

import AppKit
import WebKit

@MainActor
final class WebControls: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  let webView: WKWebView
  private var onLoad: (() -> Void)?

  init(onLoad: @escaping () -> Void) {
    self.onLoad = onLoad
    let configuration = WKWebViewConfiguration()
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()
    configuration.userContentController.add(self, name: "fixture")
    webView.navigationDelegate = self
    webView.heightAnchor.constraint(equalToConstant: 330).isActive = true
    guard let page = Bundle.main.url(forResource: "page", withExtension: "html") else {
      fatalError("page.html is missing from the fixture's resources")
    }
    webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
  }

  /// Selects `text` in the web control `id`; calls back with the selected text or "error: …".
  func select(_ command: FixtureCommand, completion: @escaping (String) -> Void) {
    webView.window?.makeFirstResponder(webView)
    var arguments: [String: Any] = ["control": command.control, "text": command.text]
    arguments["content"] = command.content ?? NSNull()
    webView.callAsyncJavaScript(
      "return window.dictFixture.select(control, text, content)", arguments: arguments,
      in: nil, in: .page
    ) { result in
      switch result {
      case .success(let value): completion(value as? String ?? "error: no result")
      case .failure(let error): completion("error: \(error.localizedDescription)")
      }
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    onLoad?()
    onLoad = nil
  }

  func userContentController(
    _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    guard let body = message.body as? [String: Any],
      let event = (body["event"] as? String).flatMap(FixtureEvent.init(rawValue:))
    else { return }
    EventLog.shared.record(
      event, control: body["control"] as? String ?? "", detail: body["detail"] as? String ?? "")
  }
}
