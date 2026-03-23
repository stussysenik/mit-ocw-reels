import WebKit

/// Pre-warmed pool of WKWebViews with YouTube IFrame Player API loaded.
///
/// Key optimization: YouTube's player JS (~200KB) downloads once and caches via
/// persistent WKWebsiteDataStore. Video switches use `player.loadVideoById()` —
/// a single JS call — instead of full page reloads.
///
/// Pool size of 3 handles: current visible + next (preload) + 1 transition buffer.
@MainActor
final class WKWebViewPool {
    static let shared = WKWebViewPool()

    private var available: [WKWebView] = []
    private var inUse = Set<ObjectIdentifier>()
    private var readySet = Set<ObjectIdentifier>()
    private let poolSize = 3
    private lazy var poolNavDelegate = PoolNavigationDelegate(pool: self)

    private init() {}

    // MARK: - Lifecycle

    /// Pre-creates pool WebViews and loads the YouTube IFrame Player API HTML.
    /// Call once during app init, after URLCache is configured.
    /// First WebView created immediately; rest staggered 1s apart to avoid
    /// thundering herd of WebContent processes at launch.
    func warmUp() {
        appendWarmWebView()
        for delay in 1..<poolSize {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Double(delay)))
                appendWarmWebView()
            }
        }
    }

    private func appendWarmWebView() {
        let webView = makeLoadedWebView()
        webView.navigationDelegate = poolNavDelegate
        available.append(webView)
    }

    /// Check out a warm WebView from the pool. Prefers HTML-ready WebViews.
    func checkout() -> WKWebView? {
        if let idx = available.lastIndex(where: { readySet.contains(ObjectIdentifier($0)) }) {
            let webView = available.remove(at: idx)
            inUse.insert(ObjectIdentifier(webView))
            return webView
        }
        guard let webView = available.popLast() else { return nil }
        inUse.insert(ObjectIdentifier(webView))
        return webView
    }

    /// Create a cold fallback when pool is exhausted (rare — fast scrolling).
    func createFallback() -> WKWebView {
        let webView = makeLoadedWebView()
        inUse.insert(ObjectIdentifier(webView))
        return webView
    }

    /// Whether the WebView's player HTML has finished loading.
    func isReady(_ webView: WKWebView) -> Bool {
        readySet.contains(ObjectIdentifier(webView))
    }

    /// Return a WebView to the pool after use.
    /// Stops playback and clears the video frame so recycled views don't flash stale content.
    func checkin(_ webView: WKWebView) {
        guard inUse.remove(ObjectIdentifier(webView)) != nil else { return }
        webView.evaluateJavaScript("stopVideo()", completionHandler: nil)
        webView.evaluateJavaScript("hidePlayer()", completionHandler: nil)
        webView.navigationDelegate = poolNavDelegate
        if available.count < poolSize {
            available.append(webView)
        } else {
            readySet.remove(ObjectIdentifier(webView))
            webView.loadHTMLString("", baseURL: nil)  // Release WebContent process
        }
    }

    /// Release idle WebViews on memory pressure. Pool self-heals via checkin.
    func handleMemoryWarning() {
        for wv in available { readySet.remove(ObjectIdentifier(wv)) }
        available.removeAll()
    }

    // MARK: - Readiness Tracking

    private class PoolNavigationDelegate: NSObject, WKNavigationDelegate {
        weak var pool: WKWebViewPool?

        init(pool: WKWebViewPool) {
            self.pool = pool
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak pool] in
                pool?.readySet.insert(ObjectIdentifier(webView))
            }
        }
    }

    // MARK: - Factory

    private func makeLoadedWebView() -> WKWebView {
        let webView = makeWebView()
        webView.loadHTMLString(Self.playerHTML, baseURL: URL(string: "https://mitreels.app"))
        return webView
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // Persistent — YouTube JS/CSS cached
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    // MARK: - YouTube IFrame Player API HTML

    /// Single HTML page loaded once per pooled WebView. The YouTube IFrame Player API
    /// downloads its JS, creates a YT.Player, and exposes `loadVideo()` for instant
    /// video switching. Time polling sends currentTime + duration every 500ms while playing.
    static let playerHTML: String = """
    <!DOCTYPE html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
    * { margin: 0; padding: 0; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
    #player { width: 100%; height: 100%; }
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
    var pendingLoad = null;
    var timePoller = null;

    function msg(s) {
        try { window.webkit.messageHandlers.ytEvent.postMessage(s); } catch(e) {}
    }

    /* API loaded — don't create player yet. Wait for loadVideo() so we can
       pass autoplay:1 in playerVars, which iOS WebKit honours natively. */
    function onYouTubeIframeAPIReady() { apiReady = true; if (pendingLoad) createPlayer(pendingLoad); }

    function createPlayer(o) {
        pendingLoad = null;
        var vars = { playsinline:1, rel:0, modestbranding:1, controls:1, fs:1, enablejsapi:1, origin:'https://mitreels.app' };
        if (o.autoplay) vars.autoplay = 1;
        if (o.captions) { vars.cc_load_policy = 1; vars.cc_lang_pref = 'en'; }
        player = new YT.Player('player', {
            videoId: o.id,
            playerVars: vars,
            events: {
                'onReady': function() {
                    playerReady = true;
                    msg('ready');
                    if (pendingLoad) { doLoad(pendingLoad); pendingLoad = null; }
                },
                'onStateChange': function(e) {
                    msg('state:' + e.data);
                    if (e.data === 1 || e.data === 5) showPlayer();
                    if (e.data === 1) startTimePolling();
                    else if (e.data === 0 || e.data === 2) stopTimePolling();
                },
                'onError': function(e) { msg('error:' + e.data); }
            }
        });
    }

    function doLoad(o) {
        if (!player) return;
        try {
            if (o.captions) { player.setOption('captions','track',{languageCode:'en'}); }
            else { player.unloadModule('captions'); }
        } catch(e) {}
        if (o.autoplay) {
            player.loadVideoById({videoId: o.id, suggestedQuality: o.quality});
        } else {
            player.cueVideoById({videoId: o.id, suggestedQuality: o.quality});
        }
    }

    function loadVideo(videoId, quality, autoplay, captions) {
        hidePlayer(); /* Hide old frame immediately; showPlayer() fires on playing/cued */
        var o = {id:videoId, quality:quality, autoplay:!!autoplay, captions:!!captions};
        if (!player) {
            /* First video — create player with autoplay in playerVars (iOS native signal) */
            if (apiReady) { createPlayer(o); } else { pendingLoad = o; }
        } else if (playerReady) {
            doLoad(o);
        } else {
            pendingLoad = o;
        }
    }

    function hidePlayer() { document.getElementById('player').style.visibility = 'hidden'; }
    function showPlayer() { document.getElementById('player').style.visibility = 'visible'; }
    function playVideo()  { if (player && playerReady) player.playVideo(); }
    function pauseVideo() { if (player && playerReady) player.pauseVideo(); }
    function stopVideo()  { if (player && playerReady) { player.stopVideo(); stopTimePolling(); } }
    function seekTo(s)    { if (player && playerReady) player.seekTo(s, true); }

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
}
