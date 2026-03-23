import SwiftUI

/// A single full-screen reel displaying a YouTube lecture video.
///
/// Minimal layout: course number + title above the video, single metadata
/// line below with OCW links. White background, no decorative elements.
struct ReelView: View {
    let lecture: Lecture

    /// Optional 0-based index; when set, shows "LECTURE N" instead of course number.
    var lectureIndex: Int? = nil

    /// Driven by the parent's scroll-position tracker. Controls auto-play/pause.
    var isVisible: Bool = false

    /// When true, preloads the video player (hidden) — covers both prev and next reels.
    var isNearby: Bool = false

    /// When false, videos won't auto-play on scroll — user must tap play manually.
    var autoplayEnabled: Bool = true

    /// When true, YouTube captions are auto-enabled (English).
    var captionsEnabled: Bool = true

    /// Callback when user taps the metadata line to navigate to the parent course.
    var onViewCourse: ((Lecture) -> Void)? = nil


    @State private var isVideoLoading = true
    @State private var hasVideoError = false
    @State private var showLiked = false
    @State private var showDisliked = false
    @State private var toastText: String?
    @State private var showFullLabels = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var seekTarget: Double? = nil

    private let sourceName: String
    private let accentColor: Color
    private let displayLabel: String
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init(
        lecture: Lecture,
        lectureIndex: Int? = nil,
        isVisible: Bool = false,
        isNearby: Bool = false,
        autoplayEnabled: Bool = true,
        captionsEnabled: Bool = true,
        onViewCourse: ((Lecture) -> Void)? = nil
    ) {
        self.lecture = lecture
        self.isNearby = isNearby
        self.lectureIndex = lectureIndex
        self.isVisible = isVisible
        self.autoplayEnabled = autoplayEnabled
        self.captionsEnabled = captionsEnabled
        self.onViewCourse = onViewCourse

        // Source-aware metadata: MIT uses school mapping, others use source branding
        if lecture.source == .mit {
            let school = MITSchool.from(courseNumber: lecture.courseNumber)
            self.sourceName = school.shortName
            self.accentColor = school.color
        } else {
            self.sourceName = lecture.source.shortName
            self.accentColor = lecture.source.brandColor
        }

        if let index = lectureIndex {
            self.displayLabel = "LECTURE \(index + 1)"
        } else {
            let num = lecture.courseNumber
            self.displayLabel = (num.isEmpty || (!num.contains(".") && num.count > 8))
                ? lecture.courseName : num
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Course number + title
            VStack(alignment: .leading, spacing: 2) {
                Text(displayLabel)
                    .font(Typography.heroNumber)
                    .foregroundStyle(CarbonColor.textPrimary)

                Text(lecture.title)
                    .font(Typography.reelTitle)
                    .foregroundStyle(CarbonColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // Video player — edge-to-edge, 16:9
            videoPlayer
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)

            // Metadata — single line: source · course left, thumbs group + chevron right
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    (Text(sourceName).foregroundStyle(accentColor)
                     + Text(" \u{00B7} ").foregroundStyle(CarbonColor.textTertiary)
                     + Text(lecture.courseName).foregroundStyle(CarbonColor.textLabel))
                        .font(Typography.reelMeta)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { showFullLabels.toggle() }
                        }

                    Spacer(minLength: Spacing.xs)

                    HStack(spacing: 0) {
                        iconButton("hand.thumbsup", filled: showLiked, activeColor: .green) {
                            haptic.impactOccurred()
                            FeedPreferences.shared.thumbsUp(sourceId: lecture.sourceId, topic: lecture.department)
                            withAnimation(.easeOut(duration: 0.15)) { showLiked = true }
                            showToast("More like this")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation { self.showLiked = false }
                            }
                        }
                        iconButton("hand.thumbsdown", filled: showDisliked, activeColor: CarbonColor.interactive) {
                            FeedPreferences.shared.thumbsDown(videoId: lecture.youtubeId, sourceId: lecture.sourceId, topic: lecture.department)
                            withAnimation(.easeOut(duration: 0.15)) { showDisliked = true }
                            showToast("Less like this")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.haptic.impactOccurred()
                            }
                        }
                    }

                    if onViewCourse != nil {
                        iconButton("chevron.right", filled: false, activeColor: .clear, font: .caption2.weight(.medium)) {
                            onViewCourse?(lecture)
                        }
                    }
                }

                // Expanded: semester · instructor (tap metadata to toggle)
                if showFullLabels, let detail = expandedDetail {
                    Text(detail)
                        .font(Typography.reelMeta)
                        .foregroundStyle(CarbonColor.textPlaceholder)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)

            // OCW links (YouTube is accessible via the overlay button on the video)
            if let courseBase = Self.courseBaseString(from: lecture.ocwUrl) {
                HStack(spacing: Spacing.md) {
                    ForEach(Self.ocwLinks(base: courseBase), id: \.label) { link in
                        Link(destination: link.url) {
                            Label(link.label, systemImage: link.icon)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(CarbonColor.textLabel)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .background(CarbonColor.reelBackground.ignoresSafeArea())
        .geometryGroup()
        .onChange(of: isVisible) { _, visible in
            isPlaying = visible && autoplayEnabled
            if !visible && !isNearby {
                isVideoLoading = true
                hasVideoError = false
                currentTime = 0
                duration = 0
            }
        }
    }

    // MARK: - URL Helpers

    /// Extracts the OCW course base URL string from a resource-level ocwUrl.
    /// e.g. "https://ocw.mit.edu/courses/6-006-.../resources/abc123/" → "https://ocw.mit.edu/courses/6-006-.../"
    static func courseBaseString(from ocwUrl: String) -> String? {
        guard !ocwUrl.isEmpty,
              let resourceRange = ocwUrl.range(of: "/resources/") else {
            return nil
        }
        return String(ocwUrl[ocwUrl.startIndex..<resourceRange.lowerBound]) + "/"
    }

    private static let ocwLinkDefs: [(label: String, icon: String, suffix: String)] = [
        ("OCW", "globe", ""),
        ("Syllabus", "list.bullet.rectangle", "pages/syllabus/"),
        ("Readings", "book", "pages/readings/"),
    ]

    static func ocwLinks(base: String) -> [(label: String, icon: String, url: URL)] {
        ocwLinkDefs.compactMap { def in
            URL(string: base + def.suffix).map { (def.label, def.icon, $0) }
        }
    }

    // MARK: - Helpers

    private func iconButton(
        _ name: String, filled: Bool, activeColor: Color,
        font: Font = .caption, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: filled ? "\(name).fill" : name)
                .font(font)
                .foregroundStyle(filled ? activeColor : CarbonColor.textTertiary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var expandedDetail: String? {
        let parts = [
            (!lecture.semester.isEmpty && lecture.year > 0) ? "\(lecture.semester) \(lecture.year)" : nil,
            (!lecture.instructor.isEmpty) ? lecture.instructor : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Video Player

    private var videoPlayer: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topTrailing) {
                YouTubeThumbnailView(videoId: lecture.youtubeId)
                    .overlay {
                        if isVisible && isVideoLoading && !hasVideoError {
                            ShimmerView()
                        }
                    }

                // Preload: create WKWebView when visible OR next (TikTok-style preloading)
                if isVisible || isNearby {
                    YouTubePlayerView(
                        videoId: lecture.youtubeId,
                        autoplay: isVisible && autoplayEnabled,
                        captionsEnabled: captionsEnabled,
                        isLoading: $isVideoLoading,
                        hasError: $hasVideoError,
                        currentTime: $currentTime,
                        duration: $duration,
                        isPlaying: $isPlaying,
                        seekTo: $seekTarget
                    )
                    .opacity(isVisible && !(isVideoLoading && !hasVideoError) ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: isVideoLoading)
                }

                if hasVideoError {
                    VStack(spacing: Spacing.xs) {
                        Image(systemName: "video.slash")
                            .font(.title)
                            .foregroundStyle(CarbonColor.textLabel)
                        Text("Video unavailable")
                            .font(.caption)
                            .foregroundStyle(CarbonColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CarbonColor.layerHover)
                    .transition(.opacity)
                }

                // YouTube deep-link — top-right corner of video
                if let ytURL = URL(string: "https://www.youtube.com/watch?v=\(lecture.youtubeId)") {
                    Link(destination: ytURL) {
                        Text("YouTube")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .padding(Spacing.sm)
                }
            }

            if isVisible && !isVideoLoading && !hasVideoError && duration > 0 {
                TimelineScrubber(currentTime: $currentTime, duration: duration) { time in
                    seekTarget = time
                }
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .overlay(alignment: .bottom) {
            if let toast = toastText {
                Text(toast)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, Spacing.md)
            }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toastText = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.3)) { toastText = nil }
        }
    }
}

#if DEBUG
#Preview {
    ReelView(lecture: PreviewSampleData.sampleLecture, isVisible: true, autoplayEnabled: true)
        .modelContainer(PreviewSampleData.container)
}
#endif
