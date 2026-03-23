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

    /// When true, preloads the video player (hidden) so it's ready when scrolled to.
    var isNext: Bool = false

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

    /// Pre-computed source label — "Engineering" for MIT, "Stanford" for Stanford, etc.
    private let sourceName: String
    /// Pre-computed accent color — school color for MIT, brand color for others.
    private let accentColor: Color
    /// Pre-computed display label — immutable for this view's lifetime.
    private let displayLabel: String

    init(
        lecture: Lecture,
        lectureIndex: Int? = nil,
        isVisible: Bool = false,
        isNext: Bool = false,
        autoplayEnabled: Bool = true,
        captionsEnabled: Bool = true,
        onViewCourse: ((Lecture) -> Void)? = nil
    ) {
        self.lecture = lecture
        self.isNext = isNext
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

            // Metadata — two rows: text on top (full width), actions below (right-aligned)
            VStack(alignment: .leading, spacing: 2) {
                // Row 1: Source · Course · Semester · Instructor — full width
                HStack(spacing: 6) {
                    Text(sourceName)
                        .font(Typography.reelMeta)
                        .foregroundStyle(accentColor)

                    Text("\u{00B7}")
                        .foregroundStyle(CarbonColor.textTertiary)

                    Text(lecture.courseName)
                        .font(Typography.reelMeta)
                        .foregroundStyle(CarbonColor.textLabel)
                        .lineLimit(showFullLabels ? nil : 1)

                    if !lecture.semester.isEmpty && lecture.year > 0 {
                        Text("\u{00B7}")
                            .foregroundStyle(CarbonColor.textTertiary)

                        Text("\(lecture.semester) \(String(lecture.year))")
                            .font(Typography.reelMeta)
                            .foregroundStyle(CarbonColor.textPlaceholder)
                    }

                    if !lecture.instructor.isEmpty {
                        Text("\u{00B7}")
                            .foregroundStyle(CarbonColor.textTertiary)

                        Text(lecture.instructor)
                            .font(Typography.reelMeta)
                            .foregroundStyle(CarbonColor.textPlaceholder)
                            .lineLimit(showFullLabels ? nil : 1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showFullLabels.toggle() }
                }

                // Row 2: Actions — right-aligned
                HStack(spacing: Spacing.sm) {
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        FeedPreferences.shared.thumbsUp(sourceId: lecture.sourceId, topic: lecture.department)
                        withAnimation(.easeOut(duration: 0.15)) { showLiked = true }
                        showToast("More like this")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { showLiked = false }
                        }
                    } label: {
                        Image(systemName: showLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.caption)
                            .foregroundStyle(showLiked ? .green : CarbonColor.textTertiary)
                            .frame(width: 36, height: 28)
                            .contentShape(Rectangle())
                    }
                    Button {
                        FeedPreferences.shared.thumbsDown(videoId: lecture.youtubeId, sourceId: lecture.sourceId, topic: lecture.department)
                        withAnimation(.easeOut(duration: 0.15)) { showDisliked = true }
                        showToast("Less like this")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: showDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.caption)
                            .foregroundStyle(showDisliked ? CarbonColor.interactive : CarbonColor.textTertiary)
                            .frame(width: 36, height: 28)
                            .contentShape(Rectangle())
                    }
                    if onViewCourse != nil {
                        Button { onViewCourse?(lecture) } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(CarbonColor.textTertiary)
                                .frame(width: 36, height: 28)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)

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
                .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)
        }
        .background(CarbonColor.reelBackground.ignoresSafeArea())
        .geometryGroup()
        .onChange(of: isVisible) { _, visible in
            isPlaying = visible && autoplayEnabled
            if !visible && !isNext {
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
                if isVisible || isNext {
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
