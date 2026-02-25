import SwiftUI

/// App settings screen accessible from the navigation bar gear button.
struct SettingsView: View {
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Experimental Features
                Section {
                    NavigationLink {
                        ExperimentalFeaturesView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "flask")
                                .font(.title3)
                                .foregroundStyle(.purple)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Experimental Features")
                                    .font(.body)

                                if featureFlags.hasAnyEnabled {
                                    Text("\(featureFlags.enabledCount) enabled")
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                } else {
                                    Text("Try upcoming features early")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if featureFlags.hasAnyEnabled {
                                Text("\(featureFlags.enabledCount)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(.purple))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Labs")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(buildNumber)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("PetTalk - Make your pets talk!")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
