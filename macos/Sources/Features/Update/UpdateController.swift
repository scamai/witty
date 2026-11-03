import Sparkle
import Cocoa
import Combine
import SwiftUI

/// Standard controller for managing Sparkle updates in Ghostty.
///
/// This controller wraps SPUStandardUpdaterController to provide a simpler interface
/// for managing updates with Ghostty's custom driver and delegate. It handles
/// initialization, starting the updater, and provides the check for updates action.
class UpdateController {
    /// Witty: the update feed and the EdDSA public key that verifies it are Witty's own,
    /// read from the Info.plist keys `SUFeedURL` and `SUPublicEDKey`. The build fills them
    /// from the `WITTY_UPDATE_FEED_URL` and `WITTY_UPDATE_PUBLIC_ED_KEY` build settings,
    /// which default to empty. Until both are set the updater stays off: Sparkle is never
    /// started, so it schedules no checks and makes no network requests, and
    /// "Check for Updates…" is hidden. A feed that `isAllowedFeedURL` refuses counts as unset.
    static let feedURL: String? = infoString("SUFeedURL").flatMap { url in
        guard isAllowedFeedURL(url) else {
            AppDelegate.logger.error("updater disabled: refusing update feed \(url, privacy: .public); it must be https, or http to a loopback address, with no query")
            return nil
        }
        return url
    }
    static let publicEDKey: String? = infoString("SUPublicEDKey")
    static var isConfigured: Bool { feedURL != nil && publicEDKey != nil }

    /// Witty: the hosts a plain `http` feed may use, so that a local test server can stand in
    /// for GitHub. `URLComponents` reports an IPv6 host with or without its brackets.
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Witty: true for an `https` URL with a host, or an `http` URL to a loopback host. Both
    /// must have no query string and no user or password, because the check is one GET of a
    /// static file that must not carry anything that could identify the user.
    static func isAllowedFeedURL(_ string: String) -> Bool {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.query == nil,
              components.user == nil,
              components.password == nil
        else { return false }

        switch scheme {
        case "https": return true
        case "http": return loopbackHosts.contains(host)
        default: return false
        }
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded "$(SETTING)" placeholder is as unset as an empty value.
        return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
    }

    private(set) var updater: SPUUpdater
    private let userDriver: UpdateDriver

    var viewModel: UpdateViewModel {
        userDriver.viewModel
    }

    /// True if we're installing an update triggered manually.
    var shouldTerminateWithoutWarning: Bool {
        viewModel.state.shouldTerminateWithoutWarning
    }

    /// Initialize a new update controller.
    init() {
        let hostBundle = Bundle.main
        self.userDriver = UpdateDriver(
            viewModel: .init(),
            hostBundle: hostBundle)
        self.updater = SPUUpdater(
            hostBundle: hostBundle,
            applicationBundle: hostBundle,
            userDriver: userDriver,
            delegate: userDriver
        )
    }

    /// Start the updater.
    ///
    /// This must be called before the updater can check for updates. If starting fails,
    /// the error will be shown to the user.
    func startUpdater() {
        guard Self.isConfigured else {
            AppDelegate.logger.info("updater disabled: no Witty update feed and key in this build")
            return
        }

        // Witty: start from no cookies for the feed's hosts, so that nothing stored by an
        // earlier version or an earlier check goes out with the first one.
        UpdateCookies.clear()

        do {
            try updater.start()
        } catch {
            userDriver.viewModel.state = .error(.init(
                error: error,
                retry: { [weak self] in
                    self?.userDriver.viewModel.state = .idle
                    self?.startUpdater()
                },
                dismiss: { [weak self] in
                    self?.userDriver.viewModel.state = .idle
                }
            ))
        }
    }

    /// Check for updates.
    ///
    /// This is typically connected to a menu item action.
    func checkForUpdates() {
        guard Self.isConfigured else { return }

        // If we're already idle, then just check for updates immediately.
        if viewModel.state == .idle {
            updater.checkForUpdates()
            return
        }

        if case let .installing(installing) = viewModel.state {
            // If the update is already installed, we can't actually
            // cancel it, and SPUUpdater.checkForUpdates will simply fail,
            // so we just show an alert to remind the user to restart.
            let alert = NSAlert()
            alert.alertStyle = .informational
            let accessoryView = NSHostingView(
                rootView: InstallingAccessoryView(installing: installing)
                    .frame(width: 228, alignment: .leading)
            )
            accessoryView.frame = .init(origin: .zero, size: accessoryView.fittingSize)
            alert.accessoryView = accessoryView
            alert.addButton(withTitle: "Restart Now")
            alert.addButton(withTitle: "Restart Later")
                .keyEquivalent = .init([KeyboardShortcut(.escape).key.character])
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                viewModel.state.confirm()
            default:
                break
            }
            return
        }

        // If we're not idle then we need to cancel any prior state.
        viewModel.state.cancel()

        // The above will take time to settle, so we delay the check for some time.
        // The 100ms is arbitrary and I'd rather not, but we have to wait more than
        // one loop tick it seems.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            self?.updater.checkForUpdates()
        }
    }
}

private struct InstallingAccessoryView: View {
    let installing: UpdateState.Installing

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Restart Required")
                    .font(.system(size: 13, weight: .semibold))

                Text("The update is ready. Please restart the application to complete the installation.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let item = installing.appcastItem, let releaseNotesURL = installing.releaseNotes?.url {
                    VStack(alignment: .leading, spacing: 4) {
                        Link(destination: releaseNotesURL) {
                            HStack(spacing: 6) {
                                Text("Version:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                Text(item.displayVersionString)
                            }
                            .font(.system(size: 11))
                        }

                        if let date = item.date {
                            HStack(spacing: 6) {
                                Text("Released:")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .trailing)
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(.system(size: 11))
                        }
                    }
                    .textSelection(.enabled)
                }
            }
        }
    }
}
