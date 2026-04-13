import WebKit
import UIKit

/// Persistent pool of 5 `WKWebView` instances for zero-wait reel playback.
///
/// Keyed by *relative position from the current center* (`-2…+2`), not by
/// lecture identity. When the user scrolls to a new center, `shift` rotates
/// slot assignments in place: the rolled-off slot's WebView is re-used
/// (not re-created) to warm the new +2 position.
///
/// All 5 WebViews share one `WKProcessPool` and `WKWebsiteDataStore.default()`
/// so `yt-player.js` downloads once and iframes re-use the cached bundle.
///
/// Warm-up sequence per slot uses `loadVideoById({mute: 1})` + `pauseVideo`
/// at time 0 — NOT `cueVideoById`. The YouTube IFrame Player API docs are
/// explicit: `cueVideoById` "does not request the video stream until
/// playVideo() or seekTo() is called." State 5 (CUED) is a metadata signal,
/// not a decoded-frame signal. Mute-autoplay-pause is the only path that
/// guarantees first-frame decode.
@MainActor
final class ReelPlayerPool {

    // MARK: - Slot

    enum SlotState: Equatable {
        case empty
        case loading
        case warming
        case warm
        case playing
        case failed(consecutiveFailures: Int)
        case recycled
    }

    @MainActor
    final class Slot {
        let webView: WKWebView
        var relativePosition: Int
        var state: SlotState = .empty
        var lectureId: String?
        var warmUpDeadline: Task<Void, Never>?

        init(webView: WKWebView, relativePosition: Int) {
            self.webView = webView
            self.relativePosition = relativePosition
        }
    }

    // MARK: - Singleton + init

    static let shared = ReelPlayerPool()

    private let capacityPerSide: Int
    private var slots: [Slot] = []
    private let processPool = WKProcessPool()
    private var navDelegate: PoolNavigationDelegate!
    private var messageHandler: PoolMessageHandler!

    init(capacityPerSide: Int = 2) {
        self.capacityPerSide = capacityPerSide
        self.navDelegate = PoolNavigationDelegate(pool: self)
        self.messageHandler = PoolMessageHandler(pool: self)
    }

    // MARK: - Public API

    /// Create 5 persistent WebViews and load the player HTML into each.
    /// Call once at app init. Staggered 250ms apart to avoid thundering-herd
    /// WebContent process spawn at launch.
    func warmUp() {
        guard slots.isEmpty else { return }
        let positions = Array(-capacityPerSide ... capacityPerSide)
        for (i, pos) in positions.enumerated() {
            let wv = makeWebView()
            let slot = Slot(webView: wv, relativePosition: pos)
            slots.append(slot)
            let delayMs = i * 250
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard self != nil else { return }
                wv.loadHTMLString(Self.playerHTML, baseURL: URL(string: "https://mitreels.app"))
            }
        }
    }

    /// Rotate slot assignments when the visible center changes.
    ///
    /// Given a new center index, compute each slot's lecture id from
    /// `lectures[index + relativePosition]`. Slots whose lecture id is
    /// unchanged (the overlap band) stay put. Slots whose lecture id
    /// changed get a new warm-up. Slots that now point outside the
    /// lecture array become `.empty`.
    func shift(toCenterIndex index: Int, in lectures: [Lecture]) {
        guard !slots.isEmpty else { return }

        for slot in slots {
            let targetIndex = index + slot.relativePosition
            let targetId: String? = (targetIndex >= 0 && targetIndex < lectures.count)
                ? lectures[targetIndex].youtubeId
                : nil

            if slot.lectureId == targetId { continue }

            slot.lectureId = targetId
            slot.warmUpDeadline?.cancel()

            if let id = targetId {
                slot.state = .loading
                scheduleWarmUpDeadline(for: slot)
                let js = "startWarm('\(id)')"
                slot.webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                slot.state = .empty
                slot.webView.evaluateJavaScript("clearSlot()", completionHandler: nil)
            }
        }

        if let center = slots.first(where: { $0.relativePosition == 0 }),
           case .warm = center.state {
            promote(center)
        }

        for slot in slots where slot.relativePosition != 0 {
            if case .playing = slot.state {
                demote(slot)
            }
        }
    }

    /// The WebView for the slot at the given relative position, or nil if
    /// the slot is outside ±capacityPerSide.
    func playerView(forRelativePosition rp: Int) -> UIView? {
        slots.first(where: { $0.relativePosition == rp })?.webView
    }

    /// Convenience: what lecture id is the slot currently assigned to?
    func lectureId(forRelativePosition rp: Int) -> String? {
        slots.first(where: { $0.relativePosition == rp })?.lectureId
    }

    /// Convenience: is a given slot's warm-up complete?
    func isReady(forRelativePosition rp: Int) -> Bool {
        guard let slot = slots.first(where: { $0.relativePosition == rp }) else { return false }
        switch slot.state {
        case .warm, .playing: return true
        default: return false
        }
    }

    /// Promote the center slot to playing (if it's warm).
    func playCenter() {
        if let center = slots.first(where: { $0.relativePosition == 0 }),
           case .warm = center.state {
            promote(center)
        }
    }

    /// Pause all non-center slots that are currently playing. Defensive:
    /// only the center should ever be in `.playing`, but if a stray slot
    /// is playing (e.g. after backward scroll before `shift` fires),
    /// demote it.
    func pauseAllButCenter() {
        for slot in slots where slot.relativePosition != 0 {
            if case .playing = slot.state { demote(slot) }
        }
    }

    /// Called on `didReceiveMemoryWarningNotification`. Recycles the -2
    /// and +2 slots (clears their iframe video state). The next `shift`
    /// call re-warms them once pressure subsides.
    ///
    /// Note: we do NOT unload the player HTML itself. `stopVideo()` releases
    /// the decoder state while keeping the player shell alive, so recovery
    /// is cheap (no `yt-player.js` re-download).
    func handleMemoryPressure() {
        for slot in slots where abs(slot.relativePosition) == capacityPerSide {
            slot.warmUpDeadline?.cancel()
            slot.state = .recycled
            slot.lectureId = nil
            slot.webView.evaluateJavaScript("clearSlot()", completionHandler: nil)
        }
    }

    // MARK: - Internal helpers (called by nav delegate + message handler)

    fileprivate func didFinishNavigation(for webView: WKWebView) {
        // HTML loaded. Slot stays in .empty until a `shift` assigns a lecture.
        // Load-bearing for jetsam recovery (Task 2.9 reloads HTML and uses
        // this hook to know the shell is ready for re-assignment).
        _ = slots.first(where: { $0.webView === webView })
    }

    fileprivate func didReceiveMessage(_ body: String, from webView: WKWebView) {
        guard let slot = slots.first(where: { $0.webView === webView }) else { return }

        if body == "apiReady" || body == "playerReady" {
            return
        }

        if body.hasPrefix("state:"), let s = Int(body.dropFirst(6)) {
            handleYouTubeState(s, slot: slot)
        } else if body.hasPrefix("error:") {
            slot.warmUpDeadline?.cancel()
            slot.state = .failed(consecutiveFailures: failureCount(slot) + 1)
        }
    }

    fileprivate func webContentProcessDidTerminate(for webView: WKWebView) {
        guard let slot = slots.first(where: { $0.webView === webView }) else { return }
        slot.warmUpDeadline?.cancel()
        slot.state = .recycled
        slot.lectureId = nil
        slot.webView.alpha = 0
        slot.webView.loadHTMLString(Self.playerHTML, baseURL: URL(string: "https://mitreels.app"))
    }

    // MARK: - Private helpers

    private func handleYouTubeState(_ state: Int, slot: Slot) {
        switch (state, slot.state) {
        case (1, .loading):
            // PLAYING (muted, off-alpha). Force the pause+seek handoff.
            slot.state = .warming
            slot.webView.evaluateJavaScript("pauseAtZero()", completionHandler: nil)
        case (2, .warming):
            // PAUSED at t=0: first frame decoded. Slot is warm.
            slot.warmUpDeadline?.cancel()
            slot.state = .warm
        case (1, .warm), (1, .playing):
            slot.state = .playing
        case (2, .playing):
            slot.state = .warm
        case (0, _):
            // Ended — stays in current state.
            break
        default:
            break
        }
    }

    private func failureCount(_ slot: Slot) -> Int {
        if case .failed(let n) = slot.state { return n }
        return 0
    }

    private func scheduleWarmUpDeadline(for slot: Slot) {
        slot.warmUpDeadline = Task { @MainActor [weak slot] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let slot else { return }
            if case .loading = slot.state { slot.state = .failed(consecutiveFailures: 1) }
            if case .warming = slot.state { slot.state = .failed(consecutiveFailures: 1) }
        }
    }

    private func promote(_ slot: Slot) {
        slot.state = .playing
        slot.webView.alpha = 1
        slot.webView.evaluateJavaScript("promoteToPlaying()", completionHandler: nil)
    }

    private func demote(_ slot: Slot) {
        slot.state = .warm
        slot.webView.alpha = 0
        slot.webView.evaluateJavaScript("demoteToWarm()", completionHandler: nil)
    }

    // MARK: - HTML + WebView factory

    private static let playerHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
    * { margin: 0; padding: 0; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
    #player { width: 100%; height: 100%; }
    #player iframe { background: transparent !important; }
    </style>
    </head>
    <body>
    <div id="player"></div>
    <script>
    var tag = document.createElement('script');
    tag.src = "https://www.youtube.com/iframe_api";
    document.head.appendChild(tag);

    var player;
    var apiReady = false;
    var playerReady = false;
    var pendingWarm = null;

    function msg(s) {
        try { window.webkit.messageHandlers.poolEvent.postMessage(s); } catch(e) {}
    }

    function onYouTubeIframeAPIReady() {
        apiReady = true;
        msg('apiReady');
        if (pendingWarm) { startWarm(pendingWarm); pendingWarm = null; }
    }

    function ensurePlayer(videoId) {
        if (player) return true;
        if (!apiReady) { pendingWarm = videoId; return false; }
        player = new YT.Player('player', {
            videoId: videoId,
            playerVars: {
                playsinline: 1, rel: 0, modestbranding: 1,
                controls: 1, fs: 1, enablejsapi: 1,
                mute: 1, autoplay: 1,
                origin: 'https://mitreels.app'
            },
            events: {
                'onReady': function() {
                    playerReady = true;
                    msg('playerReady');
                },
                'onStateChange': function(e) { msg('state:' + e.data); },
                'onError': function(e) { msg('error:' + e.data); }
            }
        });
        return true;
    }

    // Warm-up: load muted, wait for state 1 (PLAYING), pause + seek to 0.
    // The only sequence that forces YouTube's iframe to actually decode
    // the first frame. cueVideoById does NOT decode per the API docs.
    function startWarm(videoId) {
        if (!ensurePlayer(videoId)) return;
        if (playerReady) {
            player.mute();
            player.loadVideoById({ videoId: videoId, startSeconds: 0 });
        } else {
            pendingWarm = videoId;
        }
    }

    function pauseAtZero() {
        if (!player || !playerReady) return;
        player.pauseVideo();
        player.seekTo(0, true);
    }

    function promoteToPlaying() {
        if (!player || !playerReady) return;
        player.unMute();
        player.playVideo();
    }

    function demoteToWarm() {
        if (!player || !playerReady) return;
        player.pauseVideo();
        player.mute();
        player.seekTo(0, true);
    }

    function seekTo(s) { if (player && playerReady) player.seekTo(s, true); }
    function clearSlot() { if (player) { player.stopVideo(); } }
    </script>
    </body>
    </html>
    """

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(messageHandler, name: "poolEvent")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.scrollView.isScrollEnabled = false
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.alpha = 0
        wv.navigationDelegate = navDelegate
        return wv
    }
}

// MARK: - Nav delegate (jetsam + ready tracking)

private final class PoolNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var pool: ReelPlayerPool?
    init(pool: ReelPlayerPool) { self.pool = pool }

    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        Task { @MainActor [weak pool] in
            pool?.didFinishNavigation(for: webView)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak pool] in
            pool?.webContentProcessDidTerminate(for: webView)
        }
    }
}

// MARK: - Script message handler (YouTube state events)

private final class PoolMessageHandler: NSObject, WKScriptMessageHandler {
    weak var pool: ReelPlayerPool?
    init(pool: ReelPlayerPool) { self.pool = pool }

    func userContentController(_ ucc: WKUserContentController, didReceive msg: WKScriptMessage) {
        guard let body = msg.body as? String, let wv = msg.webView else { return }
        Task { @MainActor [weak pool] in
            pool?.didReceiveMessage(body, from: wv)
        }
    }
}
