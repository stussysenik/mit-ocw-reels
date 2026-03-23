import SwiftUI

/// Shared "Lecture Sources" toggle section — MIT always-on + toggleable sources.
/// Used in both the Discover filter sheet and the Courses settings sheet.
struct SourceFilterSection: View {
    @ObservedObject var sourcePrefs: SourcePreferences

    var body: some View {
        Section {
            HStack(spacing: Spacing.sm) {
                Circle().fill(UniversitySource.mit.brandColor).frame(width: 8, height: 8)
                Text("MIT OpenCourseWare").font(.body).foregroundStyle(CarbonColor.textPrimary)
                Spacer()
                Text("Always On").font(.caption).foregroundStyle(CarbonColor.textPlaceholder)
            }

            ForEach(sourcePrefs.toggleableSources) { source in
                Toggle(isOn: Binding(
                    get: { sourcePrefs.isEnabled(source) },
                    set: { sourcePrefs.setEnabled(source, $0) }
                )) {
                    HStack(spacing: Spacing.sm) {
                        Circle().fill(source.brandColor).frame(width: 8, height: 8)
                        Text(source.displayName).font(.body).foregroundStyle(CarbonColor.textPrimary)
                    }
                }
                .tint(CarbonColor.interactive)
            }
        } header: {
            Text("Lecture Sources").sectionHeader()
        }
    }
}
