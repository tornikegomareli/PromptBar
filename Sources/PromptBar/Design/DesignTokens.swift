import SwiftUI

/// Panel geometry (design: PromptBar Apple Native).
/// Panel is horizontally centered and sits at ~45% from the top.
enum PanelMetrics {
    static let width: CGFloat = 660
    static let settingsWidth: CGFloat = 660
    static let errorWidth: CGFloat = 400
    /// Horizontal padding used by panel body content.
    static let contentInset: CGFloat = 16
    /// Usable content width inside the panel body.
    static var contentWidth: CGFloat { width - contentInset * 2 }
    static let verticalAnchor: CGFloat = 0.45
    /// Time budget before the panel must be on screen (PRD §26).
    static let appearBudget: Duration = .milliseconds(150)
}
