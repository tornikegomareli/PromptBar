import SwiftUI
import AppKit

// MARK: - Tags

/// A small neutral tag (design `tagStyle`).
struct Tag: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Theme.font(11.5))
            .foregroundStyle(Theme.label2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous).fill(Theme.controlFill))
            .hairlineBorder(radius: Theme.Radius.tag)
    }
}

/// An accent-tinted tag used for the detected intent (design `tagAccent`).
struct AccentTag: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Theme.font(11.5, .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous)
                    .fill(Theme.accent.opacity(0.14))
            )
    }
}

// MARK: - Quoted original

/// The original prompt shown as a quote with a leading rule (design pattern
/// used in Generating and Result).
struct QuotedOriginal: View {
    var text: String
    var size: CGFloat = 13
    var color: Color = Theme.label
    var lineLimit: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 2.5)
            Text(text)
                .font(Theme.font(size))
                .foregroundStyle(color)
                .lineSpacing(2.5)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Section label

/// An uppercase micro heading (design: 11px/600, tertiary, 0.05em tracking).
struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.font(11, .semibold))
            .tracking(0.55)
            .foregroundStyle(Theme.label3)
    }
}

// MARK: - Keycap

/// A physical-looking key (design `keycap`): control fill, hairline, and a
/// 1.5px bottom edge that reads as depth.
struct Keycap: View {
    var label: String
    var big: Bool = true

    var body: some View {
        Text(label)
            .font(Theme.font(big ? 16 : 12, .medium))
            .foregroundStyle(Theme.label)
            .frame(minWidth: big ? 38 : 26)
            .padding(.horizontal, big ? 13 : 8)
            .padding(.vertical, big ? 9 : 4)
            .background(
                RoundedRectangle(cornerRadius: big ? 8 : 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: big ? 8 : 5, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: Theme.hairline)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: big ? 1.5 : 1)
                            .padding(.horizontal, 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: big ? 8 : 5, style: .continuous))
            }
    }
}

// MARK: - Text field

/// The design's inset text field: control background, hairline, focus ring.
struct PromptTextEditor: View {
    @Binding var text: String
    var placeholder: String
    /// A definite height — `TextEditor` is greedy vertically, so a minimum
    /// would let the field swallow the whole panel.
    var height: CGFloat
    var font: Font = Theme.font(13)
    var focused: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(font)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(height: height)
                .focused(focused)
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Theme.label3)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 15)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .strokeBorder(
                    focused.wrappedValue ? Theme.accent.opacity(0.7) : Theme.separator,
                    lineWidth: focused.wrappedValue ? 2 : Theme.hairline
                )
        )
        .animation(.easeOut(duration: 0.12), value: focused.wrappedValue)
    }
}

// MARK: - Footer hint

/// The muted keyboard hint that sits at the left of action footers.
struct FooterHint: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Theme.font(11.5))
            .foregroundStyle(Theme.label3)
    }
}

// MARK: - Spinner

/// A small indeterminate spinner matching the design's generating indicator.
struct InlineSpinner: View {
    var size: CGFloat = 13
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.8)
            .stroke(Theme.label3, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

// MARK: - Layout

/// A wrapping horizontal stack for tag rows.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, total: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                total += rowHeight + spacing
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: total + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A 0.5px full-width separator.
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }
}
