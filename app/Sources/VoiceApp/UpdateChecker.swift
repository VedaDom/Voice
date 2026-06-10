import AppKit
import Foundation

/// Checks GitHub Releases for a newer version and installs it in place.
///
/// Flow: daily check of /releases/latest → if the tag is newer than the
/// running version, the menu panel shows an update banner → "Install" downloads
/// the DMG asset, copies the new Voice.app over the current one, and relaunches.
/// Notes and settings live in Application Support, so nothing is lost.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release {
        let version: String
        let dmgURL: URL
        let pageURL: URL
    }

    @Published var available: Release?
    @Published var installing = false
    @Published var error: String?

    static let repo = "Wistfare/voice"
    private static let lastCheckKey = "LastUpdateCheck"

    func checkDaily() {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if Date().timeIntervalSince1970 - last > 86400 / 2 {
            check()
        }
    }

    func check() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String,
                  let assets = obj["assets"] as? [[String: Any]],
                  let page = obj["html_url"] as? String
            else { return }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            guard let urlStr = dmg?["browser_download_url"] as? String,
                  let url = URL(string: urlStr), let pageURL = URL(string: page)
            else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                if Self.isNewer(version, than: Self.currentVersion) {
                    self.available = Release(version: version, dmgURL: url, pageURL: pageURL)
                }
            }
        }.resume()
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Download the DMG, swap the app bundle, relaunch. Falls back to opening
    /// the release page if anything blocks the in-place install.
    func install() {
        guard let release = available, !installing else { return }
        installing = true
        error = nil
        URLSession.shared.downloadTask(with: release.dmgURL) { [weak self] tmp, _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let tmp, err == nil else {
                    self.fail(release, "Download failed")
                    return
                }
                do {
                    try self.swapAndRelaunch(dmgAt: tmp)
                } catch {
                    self.fail(release, error.localizedDescription)
                }
            }
        }.resume()
    }

    private func fail(_ release: Release, _ message: String) {
        installing = false
        error = message
        NSWorkspace.shared.open(release.pageURL)
    }

    private func swapAndRelaunch(dmgAt tmp: URL) throws {
        let fm = FileManager.default
        let dmg = fm.temporaryDirectory.appendingPathComponent("Voice-update.dmg")
        try? fm.removeItem(at: dmg)
        try fm.moveItem(at: tmp, to: dmg)

        let mount = "/tmp/voice-update-mount"
        run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-quiet",
                                 "-mountpoint", mount])
        defer { run("/usr/bin/hdiutil", ["detach", mount, "-quiet"]) }

        let newApp = URL(fileURLWithPath: mount).appendingPathComponent("Voice.app")
        guard fm.fileExists(atPath: newApp.path) else {
            throw NSError(domain: "Voice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Update DMG has no Voice.app"])
        }

        let current = Bundle.main.bundleURL
        let staging = current.deletingLastPathComponent()
            .appendingPathComponent(".Voice-new.app")
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: newApp, to: staging)
        // atomic-ish swap: old → trash-name, new → current path
        let old = current.deletingLastPathComponent()
            .appendingPathComponent(".Voice-old.app")
        try? fm.removeItem(at: old)
        try fm.moveItem(at: current, to: old)
        try fm.moveItem(at: staging, to: current)
        try? fm.removeItem(at: old)

        // relaunch the updated bundle
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", current.path]
        try p.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
