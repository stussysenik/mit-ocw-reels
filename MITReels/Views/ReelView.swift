import SwiftUI

/// A single full-screen reel displaying a YouTube lecture video.
///
/// Minimal layout: course number + title above the video, single metadata
/// line below with OCW links. White background, no decorative elements.
struct ReelView: View {
    /// Posted after dislike animation — parent should advance to next reel.
    static let dislikeAdvanceNotification = Notification.Name("reelDislikeAdvance")
    /// Posted after thumbs-up — parent should refresh engine weights.
    static let likeNotification = Notification.Name("reelLike")

    let lecture: Lecture

    /// Optional 0-based index; when set, shows "LECTURE N" instead of course number.
    var lectureIndex: Int? = nil

    /// Driven by the parent's scroll-position tracker. Controls auto-play/pause.
    var isVisible: Bool = false

    /// The cell's position relative to the current visible center,
    /// e.g. -1 for "one above center," +2 for "two below center."
    /// Drives which pool slot this cell borrows.
    var relativePosition: Int = 0

    /// When false, videos won't auto-play on scroll — user must tap play manually.
    var autoplayEnabled: Bool = true

    /// When true, YouTube captions are auto-enabled (English).
    var captionsEnabled: Bool = true

    /// Callback when user taps the metadata line to navigate to the parent course.
    var onViewCourse: ((Lecture) -> Void)? = nil


    @State private var showLiked = false
    @State private var showDisliked = false
    @State private var toastText: String?
    @State private var showFullLabels = false

    /// The pool slot whose time/state this reel displays. Resolved in `init`
    /// from `ReelPlayerPool.shared.slot(forRelativePosition:)`; falls back to
    /// a shared empty sentinel when the cell is outside the pool's window.
    @ObservedObject private var slot: ReelPlayerPool.Slot

    private let sourceName: String
    private let accentColor: Color
    private let displayLabel: String
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init(
        lecture: Lecture,
        lectureIndex: Int? = nil,
        isVisible: Bool = false,
        relativePosition: Int = 0,
        autoplayEnabled: Bool = true,
        captionsEnabled: Bool = true,
        onViewCourse: ((Lecture) -> Void)? = nil
    ) {
        self.lecture = lecture
        self.relativePosition = relativePosition
        self.lectureIndex = lectureIndex
        self.isVisible = isVisible
        self.autoplayEnabled = autoplayEnabled
        self.captionsEnabled = captionsEnabled
        self.onViewCourse = onViewCourse

        // Resolve the pool slot for this cell's relative position. Cells
        // outside the ±capacityPerSide window get the shared empty sentinel,
        // which is never assigned a lecture and therefore never triggers the
        // `slot.duration > 0` scrubber gate below.
        self._slot = ObservedObject(
            wrappedValue: ReelPlayerPool.shared.slot(forRelativePosition: relativePosition)
                ?? ReelPlayerPool.Slot.empty
        )

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
                            NotificationCenter.default.post(name: ReelView.likeNotification, object: lecture.youtubeId)
                            withAnimation(.easeOut(duration: 0.15)) { showLiked = true }
                            showToast("More like this")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation { self.showLiked = false }
                            }
                        }
                        .accessibilityIdentifier("thumbsUpButton")
                        iconButton("hand.thumbsdown", filled: showDisliked, activeColor: CarbonColor.interactive) {
                            FeedPreferences.shared.thumbsDown(videoId: lecture.youtubeId, sourceId: lecture.sourceId, topic: lecture.department)
                            withAnimation(.easeOut(duration: 0.15)) { showDisliked = true }
                            showToast("Less like this")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.haptic.impactOccurred()
                            }
                            // Advance to next reel after animation plays
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                NotificationCenter.default.post(name: ReelView.dislikeAdvanceNotification, object: lecture.youtubeId)
                            }
                        }
                        .accessibilityIdentifier("thumbsDownButton")
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
                CachedThumbnailView(videoId: lecture.youtubeId)
                    .opacity(isSlotRevealed ? 0 : 1)
                    .animation(.easeOut(duration: 0.22), value: isSlotRevealed)

                PoolBorrowedPlayerView(relativePosition: relativePosition)
                    .compositingGroup()
                    .animation(.easeOut(duration: 0.22), value: isSlotRevealed)

                playStateOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(slot.state != .playing)

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

            if isVisible && slot.duration > 0 {
                TimelineScrubber(
                    currentTime: Binding(
                        get: { slot.currentTime },
                        set: { _ in /* read-only display; scrubbing handled via pool.seek */ }
                    ),
                    duration: slot.duration
                ) { time in
                    ReelPlayerPool.shared.seek(forRelativePosition: relativePosition, to: time)
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

    /// True once the pool slot has revealed its WebView (first frame decoded
    /// or playing). Drives the thumbnail crossfade — while false, the static
    /// JPG thumbnail is visible; while true, the WebView takes over.
    private var isSlotRevealed: Bool {
        switch slot.state {
        case .warming, .warm, .playing: return true
        default: return false
        }
    }

    // MARK: - Play-state overlay

    @ViewBuilder
    private var playStateOverlay: some View {
        switch slot.state {
        case .warm, .empty, .recycled:
            Button {
                haptic.impactOccurred()
                ReelPlayerPool.shared.playCenter()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .frame(width: 88, height: 88)  // generous tap target
                    .contentShape(Rectangle())
                    .offset(x: 2) // optical centering for play glyph
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        case .loading, .warming:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.2)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                .frame(width: 88, height: 88)
        case .failed:
            Button {
                haptic.impactOccurred()
                ReelPlayerPool.shared.playCenter()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .frame(width: 88, height: 88)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .playing:
            EmptyView()
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
