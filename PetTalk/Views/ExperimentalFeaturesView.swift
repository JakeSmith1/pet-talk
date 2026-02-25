import SwiftUI

/// Displays the list of experimental features with toggles, descriptions,
/// status badges, and confirmation alerts before enabling.
struct ExperimentalFeaturesView: View {
    @ObservedObject private var featureFlags = FeatureFlags.shared

    /// The experiment that is pending confirmation (user toggled ON).
    @State private var pendingExperiment: ExperimentInfo?
    @State private var showConfirmation = false

    /// The experiment that is pending disable confirmation.
    @State private var pendingDisable: ExperimentInfo?
    @State private var showDisableConfirmation = false

    var body: some View {
        List {
            headerSection

            ForEach(FeatureFlags.experiments) { experiment in
                experimentRow(experiment)
            }

            footerSection
        }
        .navigationTitle("Experimental")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Enable Experimental Feature?", isPresented: $showConfirmation, presenting: pendingExperiment) { experiment in
            Button("Enable", role: .destructive) {
                withAnimation(.spring(response: 0.35)) {
                    featureFlags.setEnabled(experiment.id, value: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { experiment in
            Text("\"\(experiment.name)\" is in \(experiment.status.label.lowercased()) stage. It may be incomplete, unstable, or change without notice. Enable it anyway?")
        }
        .alert("Disable Feature?", isPresented: $showDisableConfirmation, presenting: pendingDisable) { experiment in
            Button("Disable", role: .destructive) {
                withAnimation(.spring(response: 0.35)) {
                    featureFlags.setEnabled(experiment.id, value: false)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { experiment in
            Text("Disabling \"\(experiment.name)\" will hide its UI and stop any related background processing.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("PetTalk Labs")
                    .font(.title2.weight(.bold))

                Text("Get early access to features we are actively developing. These experiments may be incomplete or change at any time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Experiment Row

    private func experimentRow(_ experiment: ExperimentInfo) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Top row: icon, name, status badge
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(iconBackground(for: experiment))
                            .frame(width: 40, height: 40)

                        Image(systemName: experiment.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(experiment.name)
                            .font(.headline)

                        statusBadge(experiment.status)
                    }

                    Spacer()

                    Toggle("", isOn: toggleBinding(for: experiment))
                        .labelsHidden()
                        .tint(.purple)
                }

                // Description
                Text(experiment.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Navigation to feature-specific view when enabled
                if featureFlags.isEnabled(experiment.id) {
                    featureNavigationLink(for: experiment)
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Status Badge

    private func statusBadge(_ status: ExperimentStatus) -> some View {
        Text(status.label.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(status.color.opacity(0.15))
            )
    }

    // MARK: - Feature Navigation

    @ViewBuilder
    private func featureNavigationLink(for experiment: ExperimentInfo) -> some View {
        switch experiment.id {
        case "liveCameraAR":
            NavigationLink {
                LiveCameraView()
            } label: {
                featureLinkLabel(text: "Open Live Camera", icon: "camera.viewfinder")
            }
        case "aiVoiceCloning":
            NavigationLink {
                VoiceCloningView()
            } label: {
                featureLinkLabel(text: "Open Voice Cloning", icon: "waveform.and.person.filled")
            }
        case "lipShapeMatching":
            featureLinkLabel(text: "Active in Preview", icon: "checkmark.circle.fill")
                .foregroundStyle(.green)
        default:
            EmptyView()
        }
    }

    private func featureLinkLabel(text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    // MARK: - Footer

    private var footerSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("More experiments coming soon")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Helpers

    private func toggleBinding(for experiment: ExperimentInfo) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                featureFlags.isEnabled(experiment.id)
            },
            set: { newValue in
                if newValue {
                    pendingExperiment = experiment
                    showConfirmation = true
                } else {
                    pendingDisable = experiment
                    showDisableConfirmation = true
                }
            }
        )
    }

    private func iconBackground(for experiment: ExperimentInfo) -> LinearGradient {
        let colors: [Color]
        switch experiment.id {
        case "lipShapeMatching":
            colors = [.pink, .red]
        case "liveCameraAR":
            colors = [.blue, .cyan]
        case "aiVoiceCloning":
            colors = [.purple, .indigo]
        default:
            colors = [.gray, .secondary]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
