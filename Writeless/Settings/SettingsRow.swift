import SwiftUI

/// One line of the settings window: a label on the left, a control on the
/// right, and — for the microphone — a detail view under the label.
struct SettingsRow<Detail: View, Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                detail()
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }
}

extension SettingsRow where Detail == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.init(title: title, subtitle: subtitle, detail: { EmptyView() }, control: control)
    }
}
