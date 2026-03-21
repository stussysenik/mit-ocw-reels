import SwiftUI

/// A single full-screen reel displaying a YouTube lecture video.
///
/// Minimal layout: course number + title above the video, single metadata
/// line below. White background, no decorative elements.
struct ReelView: View {
    let lecture: Lecture

    /// Optional 0-based index; when set, shows "LECTURE N" instead of course number.
    var lectureIndex: Int? = nil

    /// Driven by the parent's scroll-position tracker. Controls auto-play/pause.
    var isVisible: Bool = false

    /// When false, videos won't auto-play on scroll — user must tap play manually.
    var autoplayEnabled: Bool = true

    @State private var isVideoLoading = true
    @State private var hasVideoError = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var seekTarget: Double? = nil

    private var school: MITSchool {
        MITSchool.from(courseNumber: lecture.courseNumber)
    }

    private var displayLabel: String {
        if let index = lectureIndex {
            return "LECTURE \(index + 1)"
        }
        return lecture.courseNumber
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
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // Video player — edge-to-edge, 16:9
            videoPlayer
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)

            // Single metadata line
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)

            Spacer(minLength: 0)
        }
        .background(CarbonColor.reelBackground.ignoresSafeArea())
        .onChange(of: isVisible) { _, visible in
            isPlaying = visible && autoplayEnabled
        }
    }

    // MARK: - Video Player

    private var videoPlayer: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                YouTubeThumbnailView(videoId: lecture.youtubeId)
                    .overlay {
                        if isVideoLoading && !hasVideoError {
                            ShimmerView()
                                .opacity(0.55)
                        }
                    }

                YouTubePlayerView(
                    videoId: lecture.youtubeId,
                    autoplay: isVisible && autoplayEnabled,
                    isLoading: $isVideoLoading,
                    hasError: $hasVideoError,
                    currentTime: $currentTime,
                    duration: $duration,
                    isPlaying: $isPlaying,
                    seekTo: $seekTarget
                )
                .opacity(isVideoLoading && !hasVideoError ? 0 : 1)
                .animation(.easeIn(duration: 0.3), value: isVideoLoading)

                if isVideoLoading && !hasVideoError {
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

            if !isVideoLoading && !hasVideoError && duration > 0 {
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
