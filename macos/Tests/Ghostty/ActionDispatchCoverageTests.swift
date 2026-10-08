import Foundation
import Testing

/// Guards the action switch in `Ghostty.App.swift` against silently dropping
/// core actions into its `default:` branch, which logs "unknown action" at
/// error level. That branch is only acceptable for actions a user has to bind
/// explicitly; anything the core emits on its own must have a `case`.
///
/// This reads the sources rather than calling the dispatcher because the only
/// observable difference between an explicit no-op and the default branch is
/// the log line.
struct ActionDispatchCoverageTests {
    /// Actions intentionally left to the default branch. Each one only fires
    /// from an explicit keybinding or from a renderer macOS doesn't use, so the
    /// "unknown action" log is informative rather than noise.
    private static let unhandledOnMacOS: Set<String> = [
        "GHOSTTY_ACTION_RENDER", // only the OpenGL renderer sends .redraw
        "GHOSTTY_ACTION_SET_WINDOW_TITLE",
        "GHOSTTY_ACTION_SHOW_GTK_INSPECTOR",
        "GHOSTTY_ACTION_SHOW_ON_SCREEN_KEYBOARD",
        "GHOSTTY_ACTION_TOGGLE_TAB_OVERVIEW",
        "GHOSTTY_ACTION_TOGGLE_WINDOW_DECORATIONS",
    ]

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Ghostty
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // macos
        .deletingLastPathComponent()

    private static func declaredActions() throws -> [String] {
        let header = try String(
            contentsOf: repoRoot.appendingPathComponent("include/ghostty.h"),
            encoding: .utf8
        )
        guard let end = header.range(of: "} ghostty_action_tag_e;"),
              let start = header.range(of: "typedef enum {", options: .backwards, range: header.startIndex..<end.lowerBound)
        else { return [] }
        return try identifiers(in: String(header[start.upperBound..<end.lowerBound]))
            .filter { !$0.hasSuffix("_MAX_VALUE") }
    }

    private static func dispatchedActions() throws -> Set<String> {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("macos/Sources/Ghostty/Ghostty.App.swift"),
            encoding: .utf8
        )
        let caseLines = source
            .split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("case GHOSTTY_ACTION_") }
            .joined(separator: "\n")
        return Set(try identifiers(in: caseLines))
    }

    private static func identifiers(in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "GHOSTTY_ACTION_[A-Z0-9_]+")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    @Test func headerParses() throws {
        // Without this, an unparseable header makes every other test vacuous.
        #expect(try Self.declaredActions().count > 50)
        #expect(try Self.dispatchedActions().count > 50)
    }

    @Test func lifecycleActionsHaveExplicitCases() throws {
        let dispatched = try Self.dispatchedActions()
        // Sent on every surface create/destroy; these flooded the log.
        #expect(dispatched.contains("GHOSTTY_ACTION_SIZE_LIMIT"))
        #expect(dispatched.contains("GHOSTTY_ACTION_QUIT_TIMER"))
    }

    @Test func everyDeclaredActionIsDispatchedOrAllowlisted() throws {
        let dispatched = try Self.dispatchedActions()
        let missing = try Self.declaredActions().filter {
            !dispatched.contains($0) && !Self.unhandledOnMacOS.contains($0)
        }
        #expect(missing.isEmpty, "add a case to Ghostty.App.swift (or allowlist it here): \(missing)")
    }

    @Test func allowlistIsNotStale() throws {
        let declared = Set(try Self.declaredActions())
        let dispatched = try Self.dispatchedActions()
        for action in Self.unhandledOnMacOS {
            #expect(declared.contains(action), "\(action) no longer exists in ghostty.h")
            #expect(!dispatched.contains(action), "\(action) is handled now; drop it from the allowlist")
        }
    }
}
