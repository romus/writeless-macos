import SwiftUI
import WritelessCore

/// The collapsed "Advanced" section at the foot of Settings, and the one row
/// inside it: how much the downloaded models take, and a way to delete them.
struct AdvancedSection: View {
    let preferences: Preferences
    let state: AppState
    let actions: SettingsActions

    @State private var isExpanded = false
    /// Driven a runloop turn behind `isExpanded`, so the turn animates on its
    /// own. See `toggle()`.
    @State private var chevronAngle: Double = 0
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(chevronAngle))
                    Text("Advanced")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .accessibilityLabel("Advanced")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                SettingsRow(title: "Model cache", subtitle: cacheSubtitle) {
                    Button("Clear") { isConfirmingClear = true }
                        .controlSize(.small)
                        .disabled(!canClear)
                }
            }
        }
        .confirmationDialog(
            "Clear the model cache?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive, action: actions.clearModelCache)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Write Less downloads \(preferences.model.displayName) again — "
                    + "\(ByteFormat.size(preferences.model.downloadBytes)) — the next time you dictate."
            )
        }
    }

    /// The height change and the chevron are deliberately kept in separate
    /// runloop turns. Showing the row republishes `preferredContentSize` and
    /// AppKit resizes the window on the spot; an animation running through that
    /// resize is flushed mid-flight, which is the chevron snapping. So: let the
    /// layout settle in one un-animated step, then turn the chevron alone.
    private func toggle() {
        isExpanded.toggle()
        if isExpanded { actions.refreshModelCacheSize() }

        let turned = isExpanded
        Task {
            withAnimation(.easeInOut(duration: 0.18)) { chevronAngle = turned ? 90 : 0 }
        }
    }

    /// `nil` until the size lands: the row keeps its height either way, so a
    /// placeholder would only ever be seen as a flicker.
    private var cacheSubtitle: String? {
        guard let bytes = state.modelCacheBytes else { return nil }
        return bytes > 0 ? "\(ByteFormat.size(bytes)) on disk" : "Nothing downloaded"
    }

    /// Refusing mid-download is not cosmetic: it keeps the engine from having to
    /// wait out a first Neural Engine specialization, which cannot be cancelled
    /// and runs for minutes.
    private var canClear: Bool {
        guard state.phase == .idle else { return false }
        switch state.modelStatus {
        case .downloading, .preparing: return false
        case .ready, .missing, .failed: break
        }
        return (state.modelCacheBytes ?? 0) > 0
    }
}
