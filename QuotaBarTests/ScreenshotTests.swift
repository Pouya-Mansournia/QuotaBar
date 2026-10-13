#if DEBUG
import SwiftUI
import XCTest
@testable import QuotaBar

/// Renders the UI with mock data into `docs/` for the README.
/// Skipped unless requested:
/// `TEST_RUNNER_QUOTABAR_SCREENSHOTS=1 xcodebuild test -only-testing:QuotaBarTests/ScreenshotTests …`
@MainActor
final class ScreenshotTests: XCTestCase {
    private func render(_ view: some View, appearance: NSAppearance.Name, to name: String) throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first pass (progress bars animate in).
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))

        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

        let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try data.write(to: docs.appendingPathComponent(name))
    }

    func testRenderMenu() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QUOTABAR_SCREENSHOTS"] != nil, "Screenshots not requested")

        let directory = try TemporaryDirectory()
        let suite = "QuotaBarScreenshots-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "mockMode")
        defaults.set(false, forKey: "notificationsEnabled")

        let environment = AppEnvironment(paths: directory.paths, defaults: defaults)
        await environment.store.refresh()

        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            try render(MenuContentView().environment(environment), appearance: appearance, to: "menu-\(suffix).png")
        }
        // Setup is shown before anything is connected, so use an environment without mock data.
        let fresh = try TemporaryDirectory()
        let freshSuite = "QuotaBarScreenshots-\(UUID().uuidString)"
        let freshDefaults = try XCTUnwrap(UserDefaults(suiteName: freshSuite))
        defer { freshDefaults.removePersistentDomain(forName: freshSuite) }
        try render(
            SetupView().environment(AppEnvironment(paths: fresh.paths, defaults: freshDefaults)),
            appearance: .aqua, to: "setup.png"
        )
        try render(
            ProviderSettingsTab(provider: .claude).environment(environment).frame(width: 500),
            appearance: .aqua, to: "settings-claude.png"
        )
    }
}
#endif
