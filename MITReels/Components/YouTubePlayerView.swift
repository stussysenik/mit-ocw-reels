import SwiftUI
import WebKit

/// UIViewRepresentable wrapping WKWebView to embed YouTube videos.
/// AVPlayer cannot play YouTube URLs — WKWebView iframe embed is the standard approach.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String

    func makeUIView(context: Context) -> WKWebView {
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

    func updateUIView(_ webView: WKWebView, context: Context) {
        /// Embed URL with parameters:
        /// - playsinline=1: play inside the app, not fullscreen
        /// - autoplay=0: don't auto-play (user taps to start)
        /// - rel=0: don't show related videos
        /// - modestbranding=1: minimal YouTube branding
        let embedURL = "https://www.youtube.com/embed/\(videoId)?playsinline=1&autoplay=0&rel=0&modestbranding=1"
        guard let url = URL(string: embedURL) else { return }

        // Only reload if the URL actually changed
        if webView.url?.absoluteString != embedURL {
            webView.load(URLRequest(url: url))
        }
    }
}
