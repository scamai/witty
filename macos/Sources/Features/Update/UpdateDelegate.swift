import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Witty: one feed of its own, set at build time (see UpdateController.feedURL),
        // never Ghostty's tip and release appcasts. `auto-update-channel` has no effect.
        UpdateController.feedURL
    }

    /// Called when an update is scheduled to install silently,
    /// which occurs when `auto-update = download`.
    ///
    /// When `auto-update = check`, Sparkle will call the corresponding
    /// delegate method on the responsible driver instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        viewModel.state = .installing(.init(
            appcastItem: item,
            retryTerminatingApplication: immediateInstallHandler
        ))
        AppDelegate.logger.info("Version: \(item.displayVersionString) installed silently, waiting for relaunch...")
        // Even when hasUnobtrusiveTarget is false, we don't show the alert immediately.
        // We wait until the user manually checks for updates or relaunches.
        return true
    }
}
