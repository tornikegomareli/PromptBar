import Foundation
import ServiceManagement

/// Real launch-at-login registration via `SMAppService` (macOS 13+).
///
/// Registration can legitimately fail for an unsigned / ad-hoc-signed build,
/// so `isEnabled` always reports the *system's* view rather than an intent flag.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("PromptBar: launch-at-login \(enabled ? "register" : "unregister") failed — \(error.localizedDescription)")
        }
    }
}
