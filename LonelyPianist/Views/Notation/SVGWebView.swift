import SwiftUI
import WebKit

struct SVGWebView: NSViewRepresentable {
    let svg: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            <style>
              body { margin: 0; background: white; }
              svg { width: 100%; height: auto; display: block; }
            </style>
          </head>
          <body>
            \(svg)
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

