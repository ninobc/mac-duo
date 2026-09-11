import SwiftUI

/// First launch: what it is, the one permission, and a first fold.
struct OnboardingView: View {
    @Bindable var preferences: Preferences
    let controller: FoldController
    let finish: () -> Void

    private enum Step: Int { case welcome, permission, ready, unsupported }
    @State private var step: Step = .welcome
    @State private var granted = ScreenRecordingPermission.isGranted
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var asked = false

    var body: some View {
        ZStack {
            OnboardingBackdrop(progress: progress)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .id(step)
                Spacer(minLength: 0)
                footer
            }
            .padding(36)
        }
        .frame(width: 560, height: 520)
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            if !controller.sensorAvailable { step = .unsupported }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                let now = ScreenRecordingPermission.isGranted
                if now != granted { granted = now }
            }
        }
    }

    private var progress: Double {
        switch step {
        case .welcome: return 0
        case .permission: return 0.45
        case .ready: return 1
        case .unsupported: return 0.3
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page(
                icon: nil,
                title: "Welcome to Mac Duo",
                body: "When you close your MacBook, the desktop stays exactly where it was in the room, softening into frosted light as the glass folds over it. Open the lid and it comes back into focus.\n\nThe same idea as the iPhone Duo fold, on the Mac you already own."
            )
        case .permission:
            page(
                icon: "rectangle.dashed.badge.record",
                title: "Allow Screen Recording",
                body: "To fold your desktop, Mac Duo needs to see it. macOS calls this Screen Recording. Nothing is recorded or stored: frames live on the GPU for the moment the lid is moving, then they're gone."
            )
            VStack(spacing: 10) {
                if granted {
                    Label("Screen Recording is allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else {
                    HStack(spacing: 12) {
                        Button(asked ? "Open System Settings" : "Allow Access") {
                            if asked {
                                ScreenRecordingPermission.openSettings()
                            } else {
                                asked = true
                                ScreenRecordingPermission.request()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    if asked {
                        Text("Turn on Mac Duo under Privacy & Security › Screen & System Audio Recording. You may need to quit and reopen the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.top, 8)
        case .ready:
            page(
                icon: "laptopcomputer",
                title: "You're set",
                body: "Close the lid slowly and watch. Mac Duo lives in the menu bar: change the style, preview the fold, or turn it off from there."
            )
            VStack(spacing: 14) {
                Button {
                    controller.preview()
                } label: {
                    Label("Try the fold", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!granted)
                Toggle("Launch Mac Duo at login", isOn: $launchesAtLogin)
                    .toggleStyle(.switch)
                    .onChange(of: launchesAtLogin) { _, wanted in launchesAtLogin = LaunchAtLogin.set(wanted) }
            }
            .padding(.top, 8)
        case .unsupported:
            page(
                icon: "exclamationmark.triangle",
                title: "This Mac can't fold",
                body: "Mac Duo needs the lid angle sensor found in MacBook Pro (16-inch, 2019 and later; 14-inch, 2021 and later) and MacBook Air (M2 and later). This Mac reports as \(MacModel.identifier), and no sensor answered.\n\nYou can keep Mac Duo installed; it will stay quiet."
            )
        }
    }

    private func page(icon: String?, title: String, body: String) -> some View {
        VStack(spacing: 16) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(height: 96)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 10)
            }
            Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            if step == .permission || step == .ready {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Continue") { step = granted ? .ready : .permission }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            case .permission:
                if granted {
                    Button("Continue") { step = .ready }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for now") { step = .ready }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            case .ready:
                Button("Done") {
                    preferences.hasCompletedOnboarding = true
                    finish()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            case .unsupported:
                Button("Close") {
                    preferences.hasCompletedOnboarding = true
                    finish()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A quiet gradient that warms up as the steps go by.
private struct OnboardingBackdrop: View {
    let progress: Double

    var body: some View {
        LinearGradient(
            colors: [
                Color(hue: 0.68 - 0.06 * progress, saturation: 0.35, brightness: 0.16 + 0.06 * progress),
                Color(hue: 0.06, saturation: 0.30 + 0.25 * progress, brightness: 0.30 + 0.35 * progress),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(.thinMaterial.opacity(0.85))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: progress)
    }
}
