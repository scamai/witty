import Sparkle
import Cocoa

extension UpdateDriver: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        // Witty: one feed of its own, set at build time (see UpdateController.feedURL),
        // never Ghostty's tip and release appcasts. `auto-update-channel` has no effect.
        UpdateController.feedURL
    }

    // Witty: an update check is one GET of a static file and must not identify anyone.
    // Each hook below keeps one part of that promise. Their Objective-C selectors are
    // spelled out, so Sparkle, which looks for them with respondsToSelector:, finds
    // each one whatever name Swift gives the method.

    /// Witty: no system profile, even if `SUSendProfileInfo` is turned on in the user
    /// defaults. With no allowed keys the profile is empty, so the feed URL gets no query.
    @objc(allowedSystemProfileKeysForUpdater:)
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    /// Witty: Sparkle fetches the feed with a default `URLSession`, which stores cookies in
    /// `HTTPCookieStorage.shared` and sends them back. github.com sets a year-long `_octo`
    /// cookie on every response, which would link one day's check to the next, so the
    /// cookies of the update hosts are deleted before every check and after it.
    @objc(updater:mayPerformUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        UpdateCookies.clear()
    }

    @objc(updater:didFinishLoadingAppcast:)
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        UpdateCookies.clear()
    }

    @objc(updater:didFinishUpdateCycleForUpdateCheck:error:)
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        UpdateCookies.clear()
    }

    /// Witty: the DMG download neither sends nor stores cookies. Anything stored on the
    /// way anyway is deleted when the update cycle finishes.
    @objc(updater:willDownloadUpdate:withRequest:)
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        request.httpShouldHandleCookies = false
    }

    /// Witty: the update UI never shows Sparkle's release notes (see
    /// `UpdateDriver.showUpdateReleaseNotes`), so don't fetch them: the feed stays the
    /// only request a check makes.
    @objc(updater:shouldDownloadReleaseNotesForUpdate:)
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
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

/// Witty: deletes the cookies that update checks would otherwise carry from one check to
/// the next. Witty makes no other web requests, so these cookies only ever come from
/// Sparkle.
enum UpdateCookies {
    /// github.com and the githubusercontent.com hosts that release downloads redirect
    /// to, with their subdomains. `clear` adds the feed's own host, for a loopback test
    /// server.
    private static let updateDomains = ["github.com", "githubusercontent.com"]

    /// True if a cookie for `domain` belongs to an update host. A cookie's domain is
    /// `.github.com` when it covers subdomains and `github.com` when it does not.
    static func isUpdateCookieDomain(_ domain: String, feedHost: String?) -> Bool {
        let domain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let feedHost, domain == feedHost.lowercased() { return true }
        return updateDomains.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    static func clear(
        in storage: HTTPCookieStorage = .shared,
        feedHost: String? = UpdateController.feedURL.flatMap { URLComponents(string: $0)?.host }
    ) {
        for cookie in storage.cookies ?? [] where isUpdateCookieDomain(cookie.domain, feedHost: feedHost) {
            storage.deleteCookie(cookie)
        }
    }
}
