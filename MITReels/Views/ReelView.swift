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

    /// When false, videos won't auto-play on scroll — user must tap play manually.
    var autoplayEnabled: Bool = true

    /// Callback when user taps the metadata line to navigate to the parent course.
    var onViewCourse: ((Lecture) -> Void)? = nil

    @State private var isVideoLoading = true
    @State private var hasVideoError = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var seekTarget: Double? = nil

    /// Pre-computed school — immutable for this view's lifetime.
    private let school: MITSchool
    /// Pre-computed display label — immutable for this view's lifetime.
    private let displayLabel: String

    init(
        lecture: Lecture,
        lectureIndex: Int? = nil,
        isVisible: Bool = false,
        autoplayEnabled: Bool = true,
        onViewCourse: ((Lecture) -> Void)? = nil
    ) {
        self.lecture = lecture
        self.lectureIndex = lectureIndex
        self.isVisible = isVisible
        self.autoplayEnabled = autoplayEnabled
        self.onViewCourse = onViewCourse

        self.school = MITSchool.from(courseNumber: lecture.courseNumber)
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

            // Metadata line — tappable to navigate to course when onViewCourse is set
            HStack(spacing: 6) {
                Text(school.shortName)
                    .font(Typography.reelMeta)
                    .foregroundStyle(school.color)

                Text("\u{00B7}")
                    .foregroundStyle(CarbonColor.textTertiary)

                Text(lecture.courseName)
                    .font(Typography.reelMeta)
                    .foregroundStyle(CarbonColor.textLabel)
                    .lineLimit(1)

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
                        .lineLimit(1)
                }

                if onViewCourse != nil {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(CarbonColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xs)
            .contentShape(Rectangle())
            .onTapGesture {
                onViewCourse?(lecture)
            }

            // OCW links — course page, syllabus, readings
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
        .onChange(of: isVisible) { _, visible in
            isPlaying = visible && autoplayEnabled
            if !visible {
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
            ZStack {
                YouTubeThumbnailView(videoId: lecture.youtubeId)
                    .overlay {
                        if isVisible && isVideoLoading && !hasVideoError {
                            ShimmerView()
                                .opacity(0.55)
                        }
                    }

                // Only create WKWebView when this reel is visible.
                // This ensures at most 1 WKWebView exists at a time,
                // preventing memory accumulation and crashes during scroll.
                if isVisible {
                    YouTubePlayerView(
                        videoId: lecture.youtubeId,
                        autoplay: autoplayEnabled,
                        isLoading: $isVideoLoading,
                        hasError: $hasVideoError,
                        currentTime: $currentTime,
                        duration: $duration,
                        isPlaying: $isPlaying,
                        seekTo: $seekTarget
                    )
                    .opacity(isVideoLoading && !hasVideoError ? 0 : 1)
                    .animation(.easeIn(duration: 0.3), value: isVideoLoading)
                }

                if isVisible && isVideoLoading && !hasVideoError {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .transition(.opacity)
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
            }

            if isVisible && !isVideoLoading && !hasVideoError && duration > 0 {
                TimelineScrubber(currentTime: $currentTime, duration: duration) { time in
                    seekTarget = time
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    ReelView(lecture: PreviewSampleData.sampleLecture, isVisible: true, autoplayEnabled: true)
        .modelContainer(PreviewSampleData.container)
}
#endif
