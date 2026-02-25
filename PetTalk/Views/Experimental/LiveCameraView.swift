import SwiftUI

/// Experimental view for live camera AR mouth overlay.
///
/// Shows a camera preview placeholder with start/stop controls and a
/// "Coming Soon" overlay indicating this feature is under development.
struct LiveCameraView: View {
    @StateObject private var cameraService = LiveCameraService()
    @State private var hasPermission: Bool?

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Camera preview area
                cameraPreviewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Controls bar
                controlsBar
                    .padding(.vertical, 20)
                    .padding(.horizontal)
                    .background(.ultraThinMaterial)
            }

            // "Coming Soon" overlay
            if cameraService.state != .running {
                comingSoonOverlay
            }
        }
        .navigationTitle("Live Camera AR")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            hasPermission = await LiveCameraService.checkCameraPermission()
        }
        .onDisappear {
            cameraService.stopSession()
        }
    }

    // MARK: - Camera Preview

    private var cameraPreviewArea: some View {
        ZStack {
            // Simulated camera background
            if cameraService.state == .running {
                // In production, this would be a live camera feed via UIViewRepresentable.
                // For now, show an animated gradient to indicate the camera is "active".
                LinearGradient(
                    colors: [
                        Color(white: 0.15),
                        Color(white: 0.1),
                        Color(white: 0.12),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Simulated detection overlay
                if let region = cameraService.detectedMouthRegion {
                    GeometryReader { geometry in
                        let size = geometry.size
                        let center = CGPoint(
                            x: region.center.x * size.width,
                            y: (1 - region.center.y) * size.height
                        )
                        let radius = region.radius * min(size.width, size.height)

                        Circle()
                            .stroke(Color.green, lineWidth: 2)
                            .fill(Color.green.opacity(0.15))
                            .frame(width: radius * 2, height: radius * 2)
                            .position(center)
                            .animation(.easeInOut(duration: 0.1), value: region.center.x)
                    }
                }

                // FPS indicator
                VStack {
                    HStack {
                        Spacer()
                        Text("\(Int(cameraService.currentFPS)) FPS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(.black.opacity(0.6))
                            )
                    }
                    Spacer()
                }
                .padding(12)
            } else {
                // Idle state background
                Color(white: 0.08)

                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(.white.opacity(0.3))

                    if hasPermission == false {
                        VStack(spacing: 8) {
                            Text("Camera Access Required")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Please enable camera access in Settings to use this feature.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        Text("Tap Start to begin")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    // MARK: - Controls Bar

    private var controlsBar: some View {
        HStack(spacing: 24) {
            // State indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(stateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Start / Stop button
            Button {
                toggleSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: cameraService.state == .running ? "stop.fill" : "play.fill")
                    Text(cameraService.state == .running ? "Stop" : "Start")
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(cameraService.state == .running ? Color.red : Color.blue)
                )
            }
            .disabled(cameraService.state == .starting || hasPermission == false)
        }
    }

    // MARK: - Coming Soon Overlay

    private var comingSoonOverlay: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Coming Soon")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text("Live camera AR overlay is currently in prototype stage. The full experience with real-time pet detection and mouth animation will be available in a future update.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Helpers

    private func toggleSession() {
        if cameraService.state == .running {
            cameraService.stopSession()
        } else {
            cameraService.startSession()
        }
    }

    private var stateColor: Color {
        switch cameraService.state {
        case .running:  return .green
        case .starting: return .orange
        case .error:    return .red
        default:        return .gray
        }
    }

    private var stateLabel: String {
        switch cameraService.state {
        case .idle:          return "Ready"
        case .starting:      return "Starting..."
        case .running:       return "Live"
        case .stopped:       return "Stopped"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
