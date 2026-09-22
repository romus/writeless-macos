import SwiftUI
import WritelessCore

/// Callbacks the settings window needs from the coordinator.
struct SettingsActions {
    var windowOpened: () -> Void = {}
    var windowClosed: () -> Void = {}
    var shortcutChanged: () -> Void = {}
    var inputDeviceChanged: () -> Void = {}
    var modelChanged: () -> Void = {}
    var retryModelDownload: () -> Void = {}
    var refreshModelCacheSize: () -> Void = {}
    var clearModelCache: () -> Void = {}
    var hotkeyRecordingChanged: (Bool) -> Void = { _ in }
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let state: AppState
    let actions: SettingsActions

    @State private var shortcutHint: String?
    @State private var launchAtLogin = false
    @State private var launchAtLoginNeedsApproval = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow(title: "Shortcut", subtitle: shortcutHint ?? state.hotkeyStatus.message) {
                ShortcutRecorderButton(
                    shortcut: $preferences.shortcut,
                    hint: $shortcutHint,
                    onRecordingChanged: actions.hotkeyRecordingChanged
                )
            }
            Divider()

            SettingsRow(title: "Microphone") {
                InputLevelMeter(state: state)
            } control: {
                Picker("", selection: inputSelection) {
                    Text(InputDeviceCatalog.systemDefaultName)
                        .tag(InputDeviceCatalog.systemDefaultUID)
                    Divider()
                    ForEach(inputEntries) { entry in
                        Text(entry.title).tag(entry.uid)
                    }
                }
                .labelsHidden()
                .lineLimit(1)
                // Unlike the other pickers this one cannot hug its content:
                // "MacBook Pro Microphone" would squeeze the label and the
                // meter out of a 420pt window.
                .frame(maxWidth: 208, alignment: .trailing)
            }
            Divider()

            SettingsRow(title: "Model", subtitle: state.modelStatus.settingsSubtitle) {
                HStack(spacing: 10) {
                    if let prompt = state.modelStatus.downloadPrompt {
                        Button(prompt.settingsTitle, action: actions.retryModelDownload)
                            .buttonStyle(.link)
                    }
                    Picker("", selection: $preferences.modelID) {
                        ForEach(WhisperModelCatalog.all) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Divider()

            SettingsRow(title: "Language") {
                Picker("", selection: $preferences.languageCode) {
                    Text("Automatic").tag(LanguageCatalog.automaticCode)
                    Divider()
                    ForEach(LanguageCatalog.all) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()

            SettingsRow(title: "Sound on finish") {
                Toggle("", isOn: $preferences.soundOnFinish)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()

            SettingsRow(
                title: "Launch at login",
                subtitle: launchAtLoginNeedsApproval ? "Allow Write Less in System Settings" : nil
            ) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            Divider()

            SettingsRow(title: "Appearance") {
                Picker("", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Divider()

            AdvancedSection(preferences: preferences, state: state, actions: actions)

            HStack {
                Text("Version \(Bundle.main.shortVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(width: 420)
        .onChange(of: preferences.shortcut) { _, _ in actions.shortcutChanged() }
        .onChange(of: preferences.modelID) { _, _ in actions.modelChanged() }
        .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
        .onAppear(perform: syncLaunchAtLogin)
    }

    private var inputEntries: [InputDeviceEntry] {
        InputDeviceCatalog.deviceEntries(selected: preferences.inputDevice, available: state.inputDevices)
    }

    /// The picker trades in uids; the preference stores the whole device, so
    /// the name survives the microphone being unplugged.
    private var inputSelection: Binding<String> {
        Binding(
            get: { preferences.inputDevice?.uid ?? InputDeviceCatalog.systemDefaultUID },
            set: { uid in
                preferences.inputDevice = InputDeviceCatalog.device(
                    forUID: uid,
                    available: state.inputDevices,
                    remembered: preferences.inputDevice
                )
                actions.inputDeviceChanged()
            }
        )
    }

    /// System Settings can change the login item behind our back, so it is
    /// re-read every time the window appears.
    private func syncLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = LaunchAtLogin.isEnabled
        launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
        if launchAtLoginNeedsApproval {
            LaunchAtLogin.openLoginItemsSettings()
        }
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
