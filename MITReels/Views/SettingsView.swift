import SwiftUI
import SwiftData

/// Settings sheet — toggle content sources on/off.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = SourceSettings.shared
    @Query private var lectures: [Lecture]

    private func lectureCount(for sourceId: String) -> Int {
        lectures.filter { $0.source == sourceId }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(settings.sources.enumerated()), id: \.element.id) { index, source in
                        HStack(spacing: 12) {
                            Image(systemName: source.icon)
                                .font(.title3)
                                .foregroundStyle(.red)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(source.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                let count = lectureCount(for: source.id)
                                if count > 0 {
                                    Text("\(count) lectures")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: $settings.sources[index].isEnabled)
                                .labelsHidden()
                                .onChange(of: settings.sources[index].isEnabled) { _, newValue in
                                    settings.setEnabled(source.id, newValue)
                                }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Content Sources")
                } footer: {
                    Text("Enable sources to include their lectures in your feed. More sources coming soon.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
