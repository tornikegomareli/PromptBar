import SwiftUI

/// The chip that appears beside a selection. One action, because the panel it
/// opens is where the actual choices live — a chip with a menu in it would just
/// be a worse version of the panel.
struct SelectionPopupView: View {
    var onCompile: () -> Void

    var body: some View {
        Button(action: onCompile) {
            HStack(spacing: 5) {
                BrandMark(size: 13)
                Text("Compile")
                    .font(Theme.font(12, .medium))
                    .foregroundStyle(Theme.label)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Compile this into a prompt")
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.control))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: Theme.hairline)
        )
        // The panel is borderless and shadowless by itself; the popup needs to
        // read as floating above whatever text is behind it.
        .shadow(color: .black.opacity(0.28), radius: 7, y: 2)
        .padding(8)
    }
}
