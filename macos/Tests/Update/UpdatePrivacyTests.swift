import Testing
import Foundation
import Sparkle
@testable import Ghostty

/// Witty: the update check is one GET of a static HTTPS file that carries nothing that
/// could identify the user. These tests pin the guards in the updater's delegate and
/// controller that a unit test can reach; `testChecksStartAndEndWithoutGitHubCookies`
/// names the two cookie clears it cannot. The end-to-end proof (two checks against a
/// loopback feed, the second one sending no cookie from the first) is
/// `macos/scripts/update_probe.py`; see macos/AGENTS.md.
@Suite(.serialized)
@MainActor
struct UpdatePrivacyTests {
    // MARK: - Feed URL

    @Test(arguments: [
        "https://github.com/scamai/witty/releases/latest/download/appcast.xml",
        "http://127.0.0.1:8765/appcast.xml",
        "http://localhost:8765/appcast.xml",
        "http://[::1]:8765/appcast.xml",
    ])
    func testAllowedFeedURL(_ url: String) {
        #expect(UpdateController.isAllowedFeedURL(url))
    }

    @Test(arguments: [
        // Plain HTTP to anything but loopback could be read or rewritten on the way.
        "http://github.com/scamai/witty/releases/latest/download/appcast.xml",
        "http://192.168.1.10/appcast.xml",
        "http://127.0.0.1.example.com/appcast.xml",
        // A query string or credentials could carry an identifier.
        "https://github.com/scamai/witty/releases/latest/download/appcast.xml?id=1",
        "https://github.com/scamai/witty/releases/latest/download/appcast.xml?",
        "https://user:secret@github.com/scamai/witty/appcast.xml",
        // Not a web feed at all.
        "file:///tmp/appcast.xml",
        "ftp://github.com/appcast.xml",
        "https:///appcast.xml",
        "not a url",
        "",
    ])
    func testRefusedFeedURL(_ url: String) {
        #expect(!UpdateController.isAllowedFeedURL(url))
    }

    // MARK: - Cookies

    @Test(arguments: [
        ".github.com", "github.com", "GitHub.com",
        "release-assets.githubusercontent.com", ".githubusercontent.com",
    ])
    func testUpdateCookieDomain(_ domain: String) {
        #expect(UpdateCookies.isUpdateCookieDomain(domain, feedHost: nil))
    }

    @Test(arguments: [
        "example.com", "notgithub.com", "github.com.example.com", "githubusercontent.com.example.com",
    ])
    func testOtherCookieDomain(_ domain: String) {
        #expect(!UpdateCookies.isUpdateCookieDomain(domain, feedHost: nil))
    }

    @Test func testFeedHostCookieDomain() {
        #expect(UpdateCookies.isUpdateCookieDomain("127.0.0.1", feedHost: "127.0.0.1"))
        #expect(!UpdateCookies.isUpdateCookieDomain("127.0.0.1", feedHost: nil))
    }

    /// Goes through two of the delegate methods Sparkle calls, not only the helper:
    /// `updater(_:mayPerform:)` and `updater(_:didFinishUpdateCycleFor:error:)`. Removing
    /// `UpdateCookies.clear()` from either fails here.
    ///
    /// No test here reaches the other two clears. `updater(_:didFinishLoading:)` needs an
    /// `SUAppcast`, which has no public initializer, and `UpdateController.startUpdater()`
    /// returns before its clear in this test host, which has no feed. On a Mac,
    /// `macos/scripts/update_probe.py` checks what all four achieve together, end to end:
    /// it fails if a check sends a cookie set during an earlier check. The clears overlap,
    /// so the probe would not notice either of those two being removed on its own.
    @Test func testChecksStartAndEndWithoutGitHubCookies() throws {
        let storage = HTTPCookieStorage.shared
        let (driver, updater) = makeUpdater()
        defer { deleteTestCookies(from: storage) }

        let hooks: [(String, () throws -> Void)] = [
            ("mayPerform", { try driver.updater(updater, mayPerform: .updatesInBackground) }),
            ("didFinishUpdateCycleFor", {
                driver.updater(updater, didFinishUpdateCycleFor: .updatesInBackground, error: nil)
            }),
        ]
        func testCookieNames() -> Set<String> {
            Set((storage.cookies ?? []).filter { $0.value == "witty-test" }.map(\.name))
        }
        for (name, hook) in hooks {
            storage.setCookie(try #require(Self.cookie(domain: ".github.com", name: "_octo")))
            storage.setCookie(try #require(Self.cookie(domain: "release-assets.githubusercontent.com", name: "asset")))
            storage.setCookie(try #require(Self.cookie(domain: "example.com", name: "other")))
            // Without this the test would pass on a storage that refused the cookies.
            try #require(testCookieNames() == ["_octo", "asset", "other"])

            try hook()

            #expect(testCookieNames() == ["other"], "after \(name)")
        }
    }

    @Test func testUpdateDownloadSendsNoCookies() throws {
        let (driver, updater) = makeUpdater()
        let url = try #require(URL(string: "https://github.com/scamai/witty/releases/download/witty-v0.0.0/Witty.dmg"))
        let request = NSMutableURLRequest(url: url)
        #expect(request.httpShouldHandleCookies)

        driver.updater(updater, willDownloadUpdate: SUAppcastItem.empty(), with: request)

        #expect(!request.httpShouldHandleCookies)
    }

    /// Sparkle finds each hook by its Objective-C selector, not by its Swift name.
    @Test(arguments: [
        "allowedSystemProfileKeysForUpdater:",
        "updater:mayPerformUpdateCheck:error:",
        "updater:didFinishLoadingAppcast:",
        "updater:didFinishUpdateCycleForUpdateCheck:error:",
        "updater:willDownloadUpdate:withRequest:",
        "updater:shouldDownloadReleaseNotesForUpdate:",
    ])
    func testSparkleFindsTheHook(_ selector: String) {
        let (driver, _) = makeUpdater()
        #expect(driver.responds(to: NSSelectorFromString(selector)))
    }

    // MARK: - Nothing else is sent or fetched

    @Test func testNoSystemProfileKeys() {
        let (driver, updater) = makeUpdater()
        #expect(driver.allowedSystemProfileKeys(for: updater) == [])
    }

    @Test func testNoReleaseNotesDownload() {
        let (driver, updater) = makeUpdater()
        #expect(!driver.updater(updater, shouldDownloadReleaseNotesForUpdate: SUAppcastItem.empty()))
    }

    // MARK: - Helpers

    private func makeUpdater() -> (UpdateDriver, SPUUpdater) {
        let driver = UpdateDriver(viewModel: .init(), hostBundle: .main)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: driver)
        return (driver, updater)
    }

    private static func cookie(domain: String, name: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: domain,
            .path: "/",
            .name: name,
            .value: "witty-test",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600),
        ])
    }

    private func deleteTestCookies(from storage: HTTPCookieStorage) {
        for cookie in storage.cookies ?? [] where cookie.value == "witty-test" {
            storage.deleteCookie(cookie)
        }
    }
}
