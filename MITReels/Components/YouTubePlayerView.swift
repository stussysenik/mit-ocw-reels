import SwiftUI
import WebKit

/// YouTube video player backed by a pooled WKWebView with the IFrame Player API.
///
/// Videos switch via `player.loadVideoById()` — a single JS call, no page reload.
/// The YouTube Player JS is downloaded once and cached via persistent WKWebsiteDataStore.
/// Time polling sends currentTime + duration every 500ms for the timeline scrubber.
struct YouTubePlayerView: UIViewRepresentable {
    let videoId: String
    var autoplay: Bool = false
    var captionsEnabled: Bool = true
    @AppStorage("hdOnWifi") private var hdOnWifi = true
    @Binding var isLoading: Bool
    @Binding var hasError: Bool
    @Binding var currentTime: Double
    @Binding var duration: Double
    @Binding var isPlaying: Bool
    @Binding var seekTo: Double?

    private var resolvedQuality: String {
        guard hdOnWifi else { return "medium" }
        switch NetworkMonitor.shared.connectionQuality {
        case .excellent: return "hd1080"
        case .good:      return "medium"
        case .poor:      return "small"
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebViewPool.shared.checkout() ?? WKWebViewPool.shared.createFallback()
        webView.configuration.userContentController.add(context.coordinator, name: "ytEvent")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.currentVideoId = videoId

        if let safeId = Self.sanitizedVideoId(videoId) {
            let js = "loadVideo('\(safeId)','\(resolvedQuality)',\(autoplay),\(captionsEnabled))"
            if WKWebViewPool.shared.isReady(webView) {
                webView.evaluateJavaScript(js, completionHandler: nil)
                context.coordinator.startLoadTimeout()
            } else {
                context.coordinator.pendingJS = js
                // Timeout deferred to didFinish — don't count WebView process launch time
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            // JS hidePlayer() hides the iframe immediately; defer binding update
            // to avoid "Modifying state during view update" warnings.
            DispatchQueue.main.async { [self] in isLoading = true; hasError = false }
            if let safeId = Self.sanitizedVideoId(videoId) {
                let js = "loadVideo('\(safeId)','\(resolvedQuality)',\(autoplay),\(captionsEnabled))"
                if WKWebViewPool.shared.isReady(webView) {
                    webView.evaluateJavaScript(js, completionHandler: nil)
                } else {
                    context.coordinator.pendingJS = js
                }
            }
            context.coordinator.startLoadTimeout()
        }

        if context.coordinator.lastPlayingState != isPlaying {
            context.coordinator.lastPlayingState = isPlaying
            if isPlaying { context.coordinator.play() }
            else { context.coordinator.pause() }
        }

        if let seekTime = seekTo {
            context.coordinator.seek(to: seekTime)
            DispatchQueue.main.async { self.seekTo = nil }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.cancelLoadTimeout()
        coordinator.playTimeout?.cancel(); coordinator.playTimeout = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ytEvent")
        webView.navigationDelegate = nil
        coordinator.webView = nil
        WKWebViewPool.shared.checkin(webView)
    }

    // MARK: - Validation

    private static func sanitizedVideoId(_ videoId: String) -> String? {
        let pattern = /^[A-Za-z0-9_\-]{11}$/
        return videoId.wholeMatch(of: pattern) != nil ? videoId : nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: YouTubePlayerView
        weak var webView: WKWebView?
        var currentVideoId: String = ""
        var lastPlayingState: Bool = false
        var isDismantled = false
        /// Deferred loadVideo() JS — fired when the WebView's HTML finishes loading.
        var pendingJS: String?
        private var loadTimeout: Task<Void, Never>?
        var playTimeout: Task<Void, Never>?

        static let videoEndedNotification = Notification.Name("youtubeVideoEnded")
        static let videoUnavailableNotification = Notification.Name("youtubeVideoUnavailable")

        init(parent: YouTubePlayerView) {
            self.parent = parent
            self.currentVideoId = parent.videoId
        }

        // MARK: JS Bridge

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }

            if body == "ready" {
                // Player API ready — video may already be loading via pendingLoad
                return
            } else if body.hasPrefix("state:"), let state = Int(body.dropFirst(6)) {
                handleState(state)
            } else if body.hasPrefix("error:") {
                cancelLoadTimeout()
                let errorCode = Int(body.dropFirst(6)) ?? 0
                // 150 = private/restricted, 101 = removed, 100 = not found
                if [100, 101, 150].contains(errorCode) {
                    NotificationCenter.default.post(name: Self.videoUnavailableNotification, object: currentVideoId)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isLoading = false
                    self?.parent.hasError = true
                }
            } else if body.hasPrefix("time:") {
                let parts = body.dropFirst(5).split(separator: ":")
                if parts.count == 2, let t = Double(parts[0]), let d = Double(parts[1]) {
                    DispatchQueue.main.async { [weak self] in
                        self?.parent.currentTime = t
                        self?.parent.duration = d
                    }
                }
            }
        }

        private func handleState(_ state: Int) {
            switch state {
            case 1: // Playing
                cancelLoadTimeout()
                playTimeout?.cancel(); playTimeout = nil
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isLoading = false
                    self?.parent.isPlaying = true
                }
            case 2: // Paused
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isPlaying = false
                }
            case 3: // Buffering — video is loading data, cancel play timeout to avoid false positive
                playTimeout?.cancel(); playTimeout = nil
            case 5: // Cued — video ready, not playing (preload case)
                cancelLoadTimeout()
                DispatchQueue.main.async { [weak self] in
                    self?.parent.isLoading = false
                }
            case 0: // Ended
                NotificationCenter.default.post(name: Self.videoEndedNotification, object: currentVideoId)
            default: break
            }
        }

        // MARK: Commands

        func play() {
            webView?.evaluateJavaScript("playVideo()", completionHandler: nil)
            startPlayTimeout()
        }
        func pause() { webView?.evaluateJavaScript("pauseVideo()", completionHandler: nil) }
        func seek(to seconds: Double) {
            webView?.evaluateJavaScript("seekTo(\(seconds))", completionHandler: nil)
        }

        // MARK: Timeout

        func startLoadTimeout() {
            loadTimeout?.cancel()
            loadTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self, !self.isDismantled, self.parent.isLoading else { return }
                self.parent.isLoading = false
                self.parent.hasError = true
                NotificationCenter.default.post(name: Self.videoUnavailableNotification, object: self.currentVideoId)
            }
        }

        private func startPlayTimeout() {
            playTimeout?.cancel()
            playTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, !self.isDismantled, !self.parent.isPlaying else { return }
                self.parent.isLoading = false
                self.parent.hasError = true
                NotificationCenter.default.post(name: Self.videoUnavailableNotification, object: self.currentVideoId)
            }
        }

        func cancelLoadTimeout() { loadTimeout?.cancel(); loadTimeout = nil }

        // MARK: Navigation Delegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // HTML loaded — fire any deferred loadVideo command and start timeout
            if let js = pendingJS {
                pendingJS = nil
                webView.evaluateJavaScript(js, completionHandler: nil)
                startLoadTimeout()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cancelLoadTimeout()
            guard !isDismantled else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
                self?.parent.hasError = true
            }
            NotificationCenter.default.post(name: Self.videoUnavailableNotification, object: currentVideoId)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cancelLoadTimeout()
            guard !isDismantled else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
                self?.parent.hasError = true
            }
            NotificationCenter.default.post(name: Self.videoUnavailableNotification, object: currentVideoId)
        }
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
