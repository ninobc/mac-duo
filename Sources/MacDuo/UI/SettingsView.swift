import SwiftUI
import DuoCore

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let controller: FoldController
    @Bindable var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettings(preferences: preferences, controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            EffectSettingsPane(preferences: preferences, controller: controller)
                .tabItem { Label("Effect", systemImage: "wand.and.stars") }
                .tag(SettingsTab.effect)
            AdvancedSettings(preferences: preferences, controller: controller)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var preferences: Preferences
    let controller: FoldController
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var permissionGranted = ScreenRecordingPermission.isGranted
    @State private var sleepDisabled = SleepControl.isSleepDisabled()
    @State private var changingSleep = false

    var body: some View {
        Form {
            Section {
                Toggle("Fold the desktop when the lid closes", isOn: $preferences.isEnabled)
                    .disabled(!controller.sensorAvailable)
                Toggle("Bring the desktop into focus on wake", isOn: $preferences.focusOnWake)
                    .disabled(!controller.sensorAvailable)
                if preferences.focusOnWake {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The reveal plays only when the lid opens to your desktop. If macOS asks for your password first, set Lock Screen › \"Require password after display is turned off\" to a short delay.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Lock Screen Settings") { LockScreenSettings.open() }
                            .controlSize(.small)
                    }
                }
                Toggle("Launch at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, wanted in
                        launchesAtLogin = LaunchAtLogin.set(wanted)
                    }
            }
            Section {
                Toggle("Keep the Mac awake with the lid closed", isOn: $sleepDisabled)
                    .disabled(changingSleep)
                    .onChange(of: sleepDisabled) { old, wanted in
                        guard !changingSleep, wanted != SleepControl.isSleepDisabled() else { return }
                        changingSleep = true
                        Task {
                            let actual = await SleepControl.setSleepDisabled(wanted)
                            sleepDisabled = actual
                            changingSleep = false
                        }
                    }
                Text("Changes the system's sleep setting, so macOS asks for your password. The display still turns off when the lid is shut; the Mac keeps running, which uses battery and stays warm in a bag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle("Show lid angle in the menu bar", isOn: $preferences.showsAngleInMenuBar)
                    .disabled(!controller.sensorAvailable)
                Toggle("Check for updates automatically", isOn: $preferences.checksForUpdates)
            }
            Section {
                LabeledContent("Screen Recording") {
                    HStack(spacing: 8) {
                        Image(systemName: permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(permissionGranted ? .green : .orange)
                        Text(permissionGranted ? "Allowed" : "Not allowed")
                        if !permissionGranted {
                            Button("Open System Settings") { ScreenRecordingPermission.openSettings() }
                                .controlSize(.small)
                        }
                    }
                }
                LabeledContent("Lid angle sensor") {
                    Text(controller.sensorAvailable ? "Found, \(controller.sensorResolution) steps" : "Not found on \(MacModel.identifier)")
                        .foregroundStyle(controller.sensorAvailable ? .primary : .secondary)
                }
            } footer: {
                Text("Mac Duo reads the screen only while the lid is moving, and never stores or sends what it sees.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = ScreenRecordingPermission.isGranted
            launchesAtLogin = LaunchAtLogin.isEnabled
            if !changingSleep { sleepDisabled = SleepControl.isSleepDisabled() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                let granted = ScreenRecordingPermission.isGranted
                if granted != permissionGranted { permissionGranted = granted }
            }
        }
    }
}

// MARK: - Effect

private struct EffectSettingsPane: View {
    @Bindable var preferences: Preferences
    let controller: FoldController
    @State private var scrub: Double = 0
    @State private var isScrubbing = false

    private var presetBinding: Binding<String> {
        Binding(
            get: { preferences.preset?.rawValue ?? "custom" },
            set: { raw in
                if let preset = EffectPreset(rawValue: raw) { preferences.apply(preset) }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Style", selection: presetBinding) {
                    ForEach(EffectPreset.allCases, id: \.rawValue) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
                HStack {
                    Button("Preview Fold") { controller.preview() }
                        .disabled(!canRun)
                    Spacer()
                    Text(canRun ? "Or drag to fold the screen yourself:" : "Needs Screen Recording access")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $scrub, in: 0...1) { editing in
                    isScrubbing = editing
                    controller.scrub(to: editing ? angle(for: scrub) : nil)
                }
                .disabled(!canRun)
                .onChange(of: scrub) { _, value in
                    if isScrubbing { controller.scrub(to: angle(for: value)) }
                }
                .onAppear { scrub = 0 }
            } header: {
                Text("Try it")
            }

            Section("Timing") {
                row("Starts at", value: $preferences.effect.startAngle, in: 40...125, step: 1, format: "%.0f°",
                    help: "The fold begins when the lid closes past this angle.")
                row("Reaches full strength after", value: $preferences.effect.span, in: 15...90, step: 1, format: "%.0f°",
                    help: "Degrees of further closing until the frost is complete.")
            }

            Section("Look") {
                row("Frost", value: $preferences.effect.blurRadius, in: 16...180, step: 2, format: "%.0f pt",
                    help: "Blur at the far edge when fully folded.")
                row("Darkness", value: $preferences.effect.dimming, in: 0...1, step: 0.05, format: "%.0f%%", scale: 100,
                    help: "How dark the far edge goes.")
                row("Darkness reaches", value: $preferences.effect.dimReach, in: 0.2...1, step: 0.05, format: "%.0f%% height", scale: 100,
                    help: "Everything above this height goes fully dark at full fold.")
                row("Sheen", value: $preferences.effect.sheen, in: 0...1, step: 0.05, format: "%.0f%%", scale: 100,
                    help: "A soft light that crosses the glass mid-fold.")
            }

            Section("Perspective") {
                row("Depth", value: $preferences.effect.depth, in: 0...1.6, step: 0.05, format: "%.2f×",
                    help: "1 holds the picture exactly where it was in the room. 0 keeps it flat on the glass.")
                row("Viewing distance", value: $preferences.effect.eyeDistance, in: 1.2...5, step: 0.1, format: "%.1f screens",
                    help: "How far your eyes are from the screen, in screen heights.")
                Toggle("Keep the picture live while folding", isOn: $preferences.effect.livePicture)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Duo") { preferences.apply(.duo) }
                        .disabled(preferences.preset == .duo)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var canRun: Bool {
        controller.status == .ready || controller.status == .off
    }

    private func angle(for t: Double) -> Double {
        let effect = preferences.effect
        let open = min(effect.startAngle + 25, 135)
        let shut = max(effect.startAngle - effect.span * 1.1, 8)
        return open + (shut - open) * t
    }

    private func row(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                     format: String, scale: Double = 1, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(title)
            Text(help)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Advanced

private struct AdvancedSettings: View {
    @Bindable var preferences: Preferences
    let controller: FoldController
    @State private var copied = false
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section("Fine tuning") {
                slider("Frost at the hinge", value: $preferences.effect.blurFloor, in: 0...0.5, format: "%.0f%%", scale: 100)
                slider("Darkness begins at", value: $preferences.effect.dimStart, in: 0...0.6, format: "%.0f%% height", scale: 100)
                slider("Darkness at the hinge", value: $preferences.effect.dimHingeFloor, in: 0...0.5, format: "%.0f%%", scale: 100)
                slider("Eye height", value: $preferences.effect.eyeHeight, in: -0.3...0.5, format: "%.2f screens", scale: 1)
                slider("Grain", value: $preferences.effect.grain, in: 0...1, format: "%.0f%%", scale: 100)
            }
            Section("Sensor") {
                LabeledContent("Lid angle") {
                    Text(String(format: "%.2f°", controller.angle)).monospacedDigit()
                }
                LabeledContent("Model") { Text(MacModel.identifier) }
                LabeledContent("Resolution") { Text(controller.sensorAvailable ? controller.sensorResolution : "—") }
            }
            Section("Diagnostics") {
                HStack {
                    Button(copied ? "Copied" : "Copy Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(controller.diagnostics(), forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    }
                    Button("Show Log File") { NSWorkspace.shared.activateFileViewerSelecting([FileLog.url]) }
                }
                Text("Logs stay on this Mac, in ~/Library/Logs/Mac Duo.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Section {
                HStack {
                    Button("Show Welcome Again") { preferences.hasCompletedOnboarding = false; _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: true) }
                    Spacer()
                    Button("Reset All Settings…", role: .destructive) { confirmingReset = true }
                        .confirmationDialog("Reset every setting to its default?", isPresented: $confirmingReset) {
                            Button("Reset", role: .destructive) { preferences.resetEverything() }
                        }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: String, scale: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }

}
