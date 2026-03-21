import SwiftUI
import WebKit

/// Cross-platform ViewRepresentable wrapping WKWebView to embed YouTube videos.
///
/// Uses loadHTMLString with an iframe and a proper baseURL origin.
/// WKWebView's loadHTMLString has WebKit bug 169846 (Referer not sent on
/// cross-origin subrequests), but setting baseURL to a domain YouTube trusts
/// and including referrerpolicy + origin param works around the issue.
/// Using ocw.mit.edu as origin since these are MIT OCW videos.

#if os(iOS)
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String

    /// The origin domain used for the embed. YouTube allows embeds from
    /// this domain, and it's set as both the page baseURL and the
    /// iframe's origin parameter.
    static let embedOrigin = "https://ocw.mit.edu"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        Self.makeConfiguredWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentVideoId != videoId else { return }
        context.coordinator.currentVideoId = videoId

        webView.loadHTMLString(
            Self.embedHTML(videoId: videoId),
            baseURL: URL(string: Self.embedOrigin)
        )
    }

    /// Creates a WKWebView configured for inline YouTube playback.
    static func makeConfiguredWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    /// Generates the HTML page that hosts a YouTube iframe embed.
    static func embedHTML(videoId: String) -> String {
        YouTubePlayerView_Shared.embedHTML(videoId: videoId, origin: embedOrigin)
    }

    /// Tracks the currently loaded videoId so we only reload when it changes.
    class Coordinator {
        var currentVideoId: String?
    }
}

#elseif os(macOS)
struct YouTubePlayerView: NSViewRepresentable {
    let videoId: String

    static let embedOrigin = "https://ocw.mit.edu"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        Self.makeConfiguredWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentVideoId != videoId else { return }
        context.coordinator.currentVideoId = videoId

        webView.loadHTMLString(
            Self.embedHTML(videoId: videoId),
            baseURL: URL(string: Self.embedOrigin)
        )
    }

    /// Creates a WKWebView configured for macOS YouTube playback.
    static func makeConfiguredWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    static func embedHTML(videoId: String) -> String {
        YouTubePlayerView_Shared.embedHTML(videoId: videoId, origin: embedOrigin)
    }

    class Coordinator {
        var currentVideoId: String?
    }
}
#endif

/// Shared HTML generation for both platforms.
enum YouTubePlayerView_Shared {
    static func embedHTML(videoId: String, origin: String) -> String {
        let embedURL = "https://www.youtube.com/embed/\(videoId)?playsinline=1&autoplay=0&rel=0&modestbranding=1&enablejsapi=1&origin=\(origin)"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <meta name="referrer" content="origin">
            <style>
                * { margin: 0; padding: 0; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
                iframe { width: 100vw; height: 100vh; border: none; }
            </style>
        </head>
        <body>
            <iframe
                src="\(embedURL)"
                frameborder="0"
                referrerpolicy="origin"
                allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """
    }
}
