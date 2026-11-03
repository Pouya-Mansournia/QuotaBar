import AppKit
import CryptoKit
import Foundation

/// Checks the public GitHub release and replaces a writable /Applications install.
@MainActor
final class ReleaseUpdater {
    private static let latestURL = URL(string: "https://api.github.com/repos/Pouya-Mansournia/QuotaBar/releases/latest")!
    private let destination = URL(fileURLWithPath: "/Applications/QuotaBar.app")
    private var checkTask: Task<Void, Never>?

    func start() {
        guard Bundle.main.bundleURL.standardizedFileURL == destination.standardizedFileURL else { return }
        checkTask = Task {
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    private func check() async {
        do {
            var request = URLRequest(url: Self.latestURL)
            request.setValue("QuotaBar/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  let latest = Self.version(from: release.tagName),
                  latest.compare(current, options: .numeric) == .orderedDescending,
                  let asset = release.assets.first(where: { $0.name == "QuotaBar-macOS-\(latest).zip" }),
                  asset.size > 0, asset.size < 250_000_000,
                  asset.digest.hasPrefix("sha256:"),
                  asset.url.host == "github.com",
                  asset.url.path.hasPrefix("/Pouya-Mansournia/QuotaBar/releases/download/")
            else { return }
            try await install(asset: asset, version: latest)
        } catch {
            AppLog.shared.error("Update check failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func version(from tag: String) -> String? {
        let candidate = tag.hasPrefix("Windows-v") ? String(tag.dropFirst(9)) : String(tag.drop(while: { $0 == "v" }))
        let parts = candidate.split(separator: ".")
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return candidate
    }

    private func install(asset: Release.Asset, version: String) async throws {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("QuotaBar-update-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        let (downloaded, _) = try await URLSession.shared.download(from: asset.url)
        let zip = work.appendingPathComponent("update.zip")
        try fileManager.moveItem(at: downloaded, to: zip)
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        guard data.count == asset.size,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == String(asset.digest.dropFirst(7)).lowercased()
        else { return }

        guard try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]).status == 0 else { return }
        let candidate = work.appendingPathComponent("QuotaBar.app", isDirectory: true)
        guard let bundle = Bundle(url: candidate),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version,
              try Self.isSameSigner(current: destination, candidate: candidate)
        else { return }

        // Replacing an app requires write access to /Applications. Leave the
        // current version running if the user installed it with another owner.
        guard fileManager.isWritableFile(atPath: destination.deletingLastPathComponent().path) else { return }
        let staged = destination.deletingLastPathComponent().appendingPathComponent("QuotaBar-update-\(UUID().uuidString).app")
        try fileManager.copyItem(at: candidate, to: staged)
        defer { try? fileManager.removeItem(at: staged) }
        _ = try fileManager.replaceItemAt(destination, withItemAt: staged)

        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 2; /usr/bin/open -n \"$1\"", "sh", destination.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    private static func isSameSigner(current: URL, candidate: URL) throws -> Bool {
        let old = try run("/usr/bin/codesign", ["-dv", "--verbose=2", current.path])
        let new = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
        let candidateInfo = try run("/usr/bin/codesign", ["-dv", "--verbose=2", candidate.path])
        guard old.status == 0, new.status == 0, candidateInfo.status == 0 else { return false }
        func team(_ output: String) -> String? {
            output.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") })?.split(separator: "=").last.map(String.init)
        }
        guard let expected = team(old.output), expected != "not set" else { return false }
        return team(candidateInfo.output) == expected
    }

    private static func run(_ command: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey { case tagName = "tag_name", assets }

        struct Asset: Decodable {
            let name: String
            let url: URL
            let digest: String
            let size: Int
            enum CodingKeys: String, CodingKey {
                case name, digest, size
                case url = "browser_download_url"
            }
        }
    }
}
