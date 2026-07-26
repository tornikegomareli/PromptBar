import SwiftUI
import AppKit

/// "Apple Native" theme (design: PromptBar Apple Native).
///
/// Maps the design's tokens onto **system semantic colors** rather than fixed
/// hex values, so the UI tracks light/dark, increased contrast, and the user's
/// chosen accent automatically. The design's `#007AFF` / `#0A84FF` pair is
/// exactly what `Color.accentColor` resolves to under the default Blue accent.
enum Theme {
    // MARK: - Labels & separators

    static let label = Color(nsColor: .labelColor)
    static let label2 = Color(nsColor: .secondaryLabelColor)
    static let label3 = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)

    static let accent = Color.accentColor
    static let ok = Color(nsColor: .systemGreen)
    static let warn = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)

    /// Subtle fill behind segmented tracks and tags (design `--control-fill`).
    static let controlFill = Color.primary.opacity(0.05)
    /// Grouped-box background (design `--grouped`).
    static let grouped = Color.primary.opacity(0.04)

    // MARK: - Type (SF, the system face)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Geometry

    enum Radius {
        static let panel: CGFloat = 12
        static let control: CGFloat = 6
        static let field: CGFloat = 7
        static let group: CGFloat = 9
        static let segment: CGFloat = 7.5
        static let tag: CGFloat = 5
    }

    /// The design's 0.5px hairline.
    static let hairline: CGFloat = 0.5
}

// MARK: - Building blocks

extension View {
    /// A hairline border in the system separator colour.
    func hairlineBorder(radius: CGFloat, color: Color = Theme.separator) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: Theme.hairline)
        )
    }

    /// A grouped settings box: soft fill + hairline, matching `--grouped`.
    func groupedBox(radius: CGFloat = Theme.Radius.group) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.grouped))
            .hairlineBorder(radius: radius)
    }
}

/// The brand glyph: an opening bracket `[` + a transformation arrow `→`,
/// drawn from the design's SVG path.
struct BracketArrowMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        path.move(to: p(10, 5))
        path.addLine(to: p(7.5, 5))
        path.addArc(tangent1End: p(5, 5), tangent2End: p(5, 7.5), radius: 2.5 * s)
        path.addLine(to: p(5, 16.5))
        path.addArc(tangent1End: p(5, 19), tangent2End: p(7.5, 19), radius: 2.5 * s)
        path.addLine(to: p(10, 19))
        path.move(to: p(13.5, 12))
        path.addLine(to: p(19, 12))
        path.move(to: p(16, 9))
        path.addLine(to: p(19, 12))
        path.addLine(to: p(16, 15))
        return path
    }
}

/// The accent-tinted brand mark used in the titlebar and About.
struct BrandMark: View {
    var size: CGFloat = 15
    var color: Color = Theme.accent

    var body: some View {
        BracketArrowMark()
            .stroke(color, style: StrokeStyle(lineWidth: size * 0.133, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
