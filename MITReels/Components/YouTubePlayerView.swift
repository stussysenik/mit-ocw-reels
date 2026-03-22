import SwiftUI
import WebKit

/// YouTube video player using an embedded iframe in a minimal HTML page.
///
/// Loads a local HTML page containing a YouTube `<iframe>` embed.
/// This gives the iframe a proper parent document origin, avoiding Error 153.
/// Play/pause/seek controlled via postMessage to the YouTube iframe.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    var autoplay: Bool = false
    @Binding var isLoading: Bool
    @Binding var hasError: Bool
    @Binding var currentTime: Double
    @Binding var duration: Double

    /// Set to `true`/`false` to play/pause the video externally.
    @Binding var isPlaying: Bool

    /// Set to a non-nil time (in seconds) to trigger a seek.
    /// The binding resets to `nil` after the seek is dispatched.
    @Binding var seekTo: Double?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let html = Self.embedHTML(videoId: videoId, autoplay: autoplay)
        webView.loadHTMLString(html, baseURL: URL(string: "https://mitreels.app"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            context.coordinator.hasFinishedLoad = false
            DispatchQueue.main.async { self.isLoading = true; self.hasError = false }
            let html = Self.embedHTML(videoId: videoId, autoplay: autoplay)
            webView.loadHTMLString(html, baseURL: URL(string: "https://mitreels.app"))
        }

        if context.coordinator.lastPlayingState != isPlaying {
            context.coordinator.lastPlayingState = isPlaying
            if isPlaying {
                context.coordinator.play()
            } else {
                context.coordinator.pause()
            }
        }

        if let seekTime = seekTo {
            context.coordinator.seek(to: seekTime)
            DispatchQueue.main.async { self.seekTo = nil }
        }
    }

    /// Clean up WKWebView when SwiftUI removes this view from the hierarchy.
    /// Prevents navigation delegate callbacks on deallocated Coordinator,
    /// stops background media buffering, and releases iframe resources.
    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        coordinator.webView = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    // MARK: - HTML with iframe embed

    /// Sanitized video ID — only allows [A-Za-z0-9_-]{11}
    private static func sanitizedVideoId(_ videoId: String) -> String? {
        let pattern = /^[A-Za-z0-9_\-]{11}$/
        return videoId.wholeMatch(of: pattern) != nil ? videoId : nil
    }

    private static func embedHTML(videoId: String, autoplay: Bool) -> String {
        guard let safeId = sanitizedVideoId(videoId) else {
            return "<html><body style='background:#000'></body></html>"
        }
        let autoplayParam = autoplay ? "1" : "0"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
            * { margin: 0; padding: 0; }
            html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
            iframe { width: 100%; height: 100%; border: none; }
        </style>
        </head>
        <body>
        <iframe
            id="ytplayer"
            src="https://www.youtube.com/embed/\(safeId)?playsinline=1&autoplay=\(autoplayParam)&rel=0&modestbranding=1&controls=1&fs=1&enablejsapi=1&origin=https://mitreels.app"
            allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
            allowfullscreen>
        </iframe>
        </body>
        </html>
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: YouTubePlayerView
        weak var webView: WKWebView?
        var currentVideoId: String = ""
        var lastPlayingState: Bool = false
        var hasFinishedLoad = false

        init(parent: YouTubePlayerView) {
            self.parent = parent
            self.currentVideoId = parent.videoId
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasFinishedLoad else { return }
            hasFinishedLoad = true
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadError()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadError()
        }

        private func handleLoadError() {
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
                self?.parent.hasError = true
            }
        }

        // MARK: Commands — postMessage to YouTube iframe

        private func postCommand(_ function: String, args: String = "\"\"") {
            guard let webView else { return }
            let js = "document.getElementById('ytplayer').contentWindow.postMessage('{\"event\":\"command\",\"func\":\"\(function)\",\"args\":\(args)}', '*');"
            webView.evaluateJavaScript(js) { _, error in
                if let error { print("YT command error: \(error.localizedDescription)") }
            }
        }

        func play() { postCommand("playVideo") }
        func pause() { postCommand("pauseVideo") }
        func seek(to seconds: Double) { postCommand("seekTo", args: "[\(seconds), true]") }
    }
}

#if DEBUG
#Preview {
    YouTubePlayerView(
        videoId: "nykOeWgQcHM",
        isLoading: .constant(false),
        hasError: .constant(false),
        currentTime: .constant(0),
        duration: .constant(0),
        isPlaying: .constant(false),
        seekTo: .constant(nil)
    )
    .aspectRatio(16 / 9, contentMode: .fit)
    .padding()
}
#endif
