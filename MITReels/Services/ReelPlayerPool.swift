import WebKit
import UIKit
import AVFAudio
import os

private let poolLog = Logger(subsystem: "com.mitreels.app", category: "ReelPlayerPool")

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
    final class Slot: ObservableObject {
        let webView: WKWebView
        var relativePosition: Int
        @Published var state: SlotState = .empty
        var lectureId: String?
        @Published var currentTime: Double = 0
        @Published var duration: Double = 0
        var warmUpDeadline: Task<Void, Never>?

        init(webView: WKWebView, relativePosition: Int) {
            self.webView = webView
            self.relativePosition = relativePosition
        }

        /// Shared placeholder slot used by cells that fall outside the pool's
        /// ±capacityPerSide window. `@ObservedObject` needs a non-nil value,
        /// so we hand out this sentinel. Lazy-init via `static let` means the
        /// backing `WKWebView` is created exactly once for the lifetime of
        /// the process — one extra WebContent process, not per cell.
        static let empty: Slot = Slot(webView: WKWebView(), relativePosition: 999)
    }

    // MARK: - Singleton + init

    static let shared = ReelPlayerPool()

    private let capacityPerSide: Int
    private var slots: [Slot] = []
    private let processPool = WKProcessPool()
    private var navDelegate: PoolNavigationDelegate!
    private var messageHandler: PoolMessageHandler!

    /// When true, the center slot auto-promotes to `.playing` as soon as its
    /// warm-up completes (state 2 arrives). When false, the user must tap
    /// play explicitly. Kept in sync with `@AppStorage("autoplayEnabled")`
    /// from `DiscoverView`.
    var autoplayEnabled: Bool = true

    /// Snapshot of whether the center was playing at the moment we backgrounded,
    /// so `handleSceneForeground()` can restore it without the user re-tapping.
    private var wasPlayingBeforeBackground: Bool = false

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
        configureAudioSession()
        observeAudioInterruptions()
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

    /// Configure `AVAudioSession` for video playback. Uses `.playback` so the
    /// app mixes with / ducks other audio sources correctly, and so that audio
    /// survives ringer-off + lock-screen transitions without being silenced.
    /// `.moviePlayback` mode tells iOS "this is video, apply normal EQ / no
    /// speech-processing tuning."
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            poolLog.error("AVAudioSession configure failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Listen for AVAudioSession interruptions (phone call, Siri, other apps
    /// taking audio focus) so the center slot pauses when audio is yanked and
    /// resumes cleanly when the interruption ends — standard iOS contract.
    private func observeAudioInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            Task { @MainActor in self.handleAudioInterruption(note) }
        }
    }

    private func handleAudioInterruption(_ note: Notification) {
        guard let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // Something else is taking audio — pause so we're polite, remember
            // state so we can resume when the interruption ends.
            if let center = slots.first(where: { $0.relativePosition == 0 }),
               case .playing = center.state {
                wasPlayingBeforeBackground = true
                demote(center)
            }
        case .ended:
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if options.contains(.shouldResume), wasPlayingBeforeBackground {
                wasPlayingBeforeBackground = false
                playCenter()
            }
        @unknown default:
            break
        }
    }

    /// Called on scene transition to background/inactive. Pauses the currently
    /// playing center slot and snapshots state so `handleSceneForeground()` can
    /// restore playback without re-warming — continuity-friction-free.
    func handleSceneBackground() {
        guard let center = slots.first(where: { $0.relativePosition == 0 }) else { return }
        if case .playing = center.state {
            wasPlayingBeforeBackground = true
            demote(center)
        }
    }

    /// Called on scene transition back to foreground. If the center was playing
    /// before backgrounding, resume from its persisted playhead (WKWebView
    /// retains iframe state across scene phases, so playhead is preserved
    /// natively — we just unmute + play).
    func handleSceneForeground() {
        guard wasPlayingBeforeBackground else { return }
        wasPlayingBeforeBackground = false
        playCenter()
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
                // Hide the old slot's lingering paused frame while the new
                // lecture is warming — the thumbnail fallback underneath takes
                // over for ~200-500ms until .warming fires.
                slot.webView.alpha = 0
                poolLog.info("slot \(slot.relativePosition, privacy: .public) → loading yt=\(id, privacy: .public)")
                scheduleWarmUpDeadline(for: slot)
                let js = "startWarm('\(id)')"
                slot.webView.evaluateJavaScript(js, completionHandler: nil)
            } else {
                slot.state = .empty
                slot.webView.alpha = 0
                poolLog.info("slot \(slot.relativePosition, privacy: .public) → empty")
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

    /// Observable slot for a relative position. SwiftUI views can
    /// `@ObservedObject` this to get state/time updates.
    func slot(forRelativePosition rp: Int) -> Slot? {
        slots.first(where: { $0.relativePosition == rp })
    }

    /// Seek the player at the given relative slot to `seconds`. No-op when
    /// the slot is outside the pool's active window.
    func seek(forRelativePosition rp: Int, to seconds: Double) {
        guard let slot = slots.first(where: { $0.relativePosition == rp }) else { return }
        slot.webView.evaluateJavaScript("seekTo(\(seconds))", completionHandler: nil)
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
            slot.webView.alpha = 0
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

        if body == "apiReady" {
            poolLog.info("slot \(slot.relativePosition, privacy: .public) msg: apiReady")
            // Self-heal: if this slot was marked .failed by an over-eager
            // deadline (e.g. cold-start overshoot) but the iframe API finally
            // arrived, reset to .loading and re-issue the warm-up so the slot
            // recovers without needing the user to scroll.
            if case .failed = slot.state, let lectureId = slot.lectureId {
                poolLog.info("slot \(slot.relativePosition, privacy: .public) recovering .failed → .loading")
                slot.state = .loading
                scheduleWarmUpDeadline(for: slot)
                slot.webView.evaluateJavaScript("startWarm('\(lectureId)')", completionHandler: nil)
            }
            return
        }
        if body == "playerReady" {
            poolLog.info("slot \(slot.relativePosition, privacy: .public) msg: playerReady")
            return
        }

        if body.hasPrefix("state:"), let s = Int(body.dropFirst(6)) {
            poolLog.info("slot \(slot.relativePosition, privacy: .public) yt-state \(s, privacy: .public)")
            handleYouTubeState(s, slot: slot)
        } else if body.hasPrefix("time:") {
            let parts = body.dropFirst(5).split(separator: ":")
            if parts.count == 2, let t = Double(parts[0]), let d = Double(parts[1]) {
                slot.currentTime = t
                slot.duration = d
            }
        } else if body.hasPrefix("error:") {
            poolLog.error("slot \(slot.relativePosition, privacy: .public) msg: \(body, privacy: .public)")
            slot.warmUpDeadline?.cancel()
            slot.state = .failed(consecutiveFailures: failureCount(slot) + 1)
        } else if body.hasPrefix("console:") {
            poolLog.info("slot \(slot.relativePosition, privacy: .public) console: \(body.dropFirst(8), privacy: .public)")
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
            // PLAYING (muted). Reveal the WebView — at this moment the iframe
            // is actually rendering frames, so we crossfade away from the
            // static JPG thumbnail under us. Then force the pause+seek handoff
            // so the player settles on the first frame.
            slot.state = .warming
            slot.webView.alpha = 1
            slot.webView.evaluateJavaScript("pauseAtZero()", completionHandler: nil)
        case (2, .warming):
            // PAUSED at t=0: first frame decoded. Slot is warm.
            slot.warmUpDeadline?.cancel()
            slot.state = .warm
            // Auto-promote the center slot the moment it warms — this is the
            // "zero-wait" promise of the pool. Without this, the center would
            // sit in .warm forever unless the user tapped play explicitly.
            if slot.relativePosition == 0 && autoplayEnabled {
                promote(slot)
            }
        case (1, .warm), (1, .playing):
            slot.state = .playing
        case (2, .playing):
            slot.state = .warm
        case (0, _):
            // Ended — stays in current state, but if this is the center slot,
            // post a notification so DiscoverView can advance to the next reel.
            if slot.relativePosition == 0, let lectureId = slot.lectureId {
                NotificationCenter.default.post(
                    name: .reelPlayerPoolVideoEnded,
                    object: lectureId
                )
            }
        default:
            break
        }
    }

    private func failureCount(_ slot: Slot) -> Int {
        if case .failed(let n) = slot.state { return n }
        return 0
    }

    private func scheduleWarmUpDeadline(for slot: Slot) {
        // Cold-start budget: spawning 5 WebContent processes + fetching
        // iframe_api.js + bootstrapping YT can burn 12-18s on a fresh
        // device/simulator. 10s was too tight and tripped on every cold
        // start; 25s is a "something is actually wrong" threshold, not a
        // performance budget.
        slot.warmUpDeadline = Task { @MainActor [weak slot] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let slot else { return }
            if case .loading = slot.state {
                poolLog.error("slot \(slot.relativePosition, privacy: .public) TIMEOUT in .loading (apiReady/playerReady never arrived)")
                slot.state = .failed(consecutiveFailures: 1)
            }
            if case .warming = slot.state {
                poolLog.error("slot \(slot.relativePosition, privacy: .public) TIMEOUT in .warming (state 2 never arrived)")
                slot.state = .failed(consecutiveFailures: 1)
            }
        }
    }

    private func promote(_ slot: Slot) {
        slot.state = .playing
        slot.webView.alpha = 1
        slot.webView.evaluateJavaScript("promoteToPlaying()", completionHandler: nil)
    }

    private func demote(_ slot: Slot) {
        slot.state = .warm
        // alpha stays 1 — the first frame remains visible as a "paused poster"
        // rather than snapping back to the static JPG. No continuity friction
        // when the slot demotes between .playing and .warm.
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
    // Tracks whether the caller asked to promote this slot to playing; unMute
    // + visible playback are deferred until state=1 actually arrives so audio
    // does not lead video by a frame on slower devices.
    var pendingUnmute = false;

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
                mute: 1, autoplay: 1
                // origin intentionally omitted: on physical iOS devices the
                // embedding document.origin for loadHTMLString pages doesn't
                // reliably match a hardcoded value, which causes YT to reject
                // postMessage -> onYouTubeIframeAPIReady never fires.
            },
            events: {
                'onReady': function() {
                    playerReady = true;
                    msg('playerReady');
                },
                'onStateChange': function(e) {
                    msg('state:' + e.data);
                    if (e.data === 1) {
                        startTimePolling();
                        // Deferred unMute: the moment the decoder reports
                        // PLAYING for a promotion-pending slot, drop the mute
                        // so audio and first frame land in the same frame.
                        if (pendingUnmute) {
                            pendingUnmute = false;
                            player.unMute();
                        }
                    } else if (e.data === 0 || e.data === 2) {
                        stopTimePolling();
                    }
                },
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
        // Audio-video sync: mark pending, call play, wait for state=1 in
        // onStateChange before unMute. Prevents audio leading first-frame
        // decode by a frame on slower devices.
        pendingUnmute = true;
        player.playVideo();
    }

    function demoteToWarm() {
        if (!player || !playerReady) return;
        pendingUnmute = false;
        player.pauseVideo();
        player.mute();
        player.seekTo(0, true);
    }

    function seekTo(s) { if (player && playerReady) player.seekTo(s, true); }
    function clearSlot() { if (player) { player.stopVideo(); } }

    var timePoller = null;
    function startTimePolling() {
        stopTimePolling();
        timePoller = setInterval(function() {
            if (player && player.getCurrentTime) {
                msg('time:' + (player.getCurrentTime()||0).toFixed(1) + ':' + (player.getDuration()||0).toFixed(1));
            }
        }, 500);
    }
    function stopTimePolling() {
        if (timePoller) { clearInterval(timePoller); timePoller = null; }
    }
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
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
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

// MARK: - Notification names

extension Notification.Name {
    /// Posted when the center slot's YouTube player reports state 0 (ended).
    /// The notification `object` is the lecture id that just finished.
    /// DiscoverView observes this to advance to the next reel.
    static let reelPlayerPoolVideoEnded = Notification.Name("ReelPlayerPoolVideoEnded")
}
