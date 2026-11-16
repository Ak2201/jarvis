#if !APPSTORE
import AppKit
import ApplicationServices
import SwiftUI

// The Apps pill: Claude, Xcode, Android Studio, Chrome, Arc and DaVinci Resolve at a glance.
// It reads only what macOS already shows: which apps are open, their Dock badges (through
// the Accessibility API, the permission Flow uses), and for Claude what Jarvis knows anyway
// (Claude Code sessions, the Claude app's reply, the plan gauge). Nothing runs while the pill
// is off; while it's on, one cheap look every few seconds. No text of any app is read.

@MainActor
final class AppStatusHub: ObservableObject {
    static let shared = AppStatusHub()
    static let pillId = "integration_apps"

    static var isPillActive: Bool { AppState.shared.activeIntegrations.contains(pillId) }

    @Published private(set) var statuses: [AppStatus] = []
    @Published private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private var claudeWriting = false
    private var claudeReplyReady = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTopLevel: AppLevel = .off
    /// Dock item URL → bundle id, so a Dock look doesn't open every bundle each time.
    private var bundleIdCache: [String: String] = [:]

    // Android Studio: idea.log, read from where the last look stopped.
    private var studioLog = AndroidStudioLogState()
    private var studioLogPath: String?
    private var studioLogOffset: UInt64 = 0
    // Xcode: each DerivedData manifest, parsed again only when it changes.
    private var xcodeManifests: [String: (modified: Date, latest: BuildActivity?)] = [:]
    /// The newest finished build per app that was already announced (or there at launch).
    private var announced: [String: Date] = [:]

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, WatchedApps.all.contains(where: { $0.bundleId == id }) else { return }
                MainActor.assumeIsolated { AppStatusHub.shared.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: ClaudeDesktopChatWatcher.replyNotification, object: nil, queue: .main) { note in
            guard let reply = note.object as? ClaudeDesktopReply else { return }
            MainActor.assumeIsolated { AppStatusHub.shared.claudeReply(reply) }
        })
        // The pill switched on or off in Settings.
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppStatusHub.shared.updateTimer() }
        })
        updateTimer()
    }

    private func updateTimer() {
        if Self.isPillActive {
            guard timer == nil else { return }
            refresh()
            let t = Timer(timeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated { AppStatusHub.shared.refresh() }
            }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if let t = timer {
            t.invalidate()
            timer = nil
            statuses = []
        }
    }

    private func claudeReply(_ reply: ClaudeDesktopReply) {
        switch reply {
        case .writing: claudeWriting = true; claudeReplyReady = false
        case .stopped: claudeWriting = false
        case .ready:   claudeWriting = false; claudeReplyReady = true
        case .seen:    claudeWriting = false; claudeReplyReady = false
        }
        if Self.isPillActive { refresh() }
    }

    // MARK: - Reading the Mac

    func refresh() {
        guard Self.isPillActive else { return }
        accessibilityTrusted = AXIsProcessTrusted()
        let badges = accessibilityTrusted ? dockBadges() : [:]
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))

        let new = WatchedApps.all.map { app -> AppStatus in
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) != nil
            let isRunning = running.contains(app.bundleId)
            switch app.id {
            case "claude":
                return AppStatusLogic.claude(claudeSnapshot(running: isRunning), app: app,
                                             installed: installed, badge: badges[app.bundleId])
            case "android-studio" where installed:
                readAndroidStudio()
                announce(app, [studioLog.build, studioLog.sync].compactMap { $0 })
                return AppStatusLogic.androidStudio(app: app, installed: installed, running: isRunning,
                                                    badge: badges[app.bundleId], log: studioLog)
            case "xcode" where installed:
                let latest = readXcode()
                announce(app, latest.map { [$0] } ?? [])
                return AppStatusLogic.xcode(app: app, installed: installed, running: isRunning,
                                            badge: badges[app.bundleId], latest: latest)
            default:
                break
            }
            return AppStatusLogic.generic(app: app, installed: installed, running: isRunning,
                                          badge: badges[app.bundleId])
        }
        if new != statuses { statuses = new }
        updatePill()
    }

    private func claudeSnapshot(running: Bool) -> ClaudeSnapshot {
        let state = AppState.shared
        var s = ClaudeSnapshot()
        s.desktopRunning = running
        s.desktopWriting = running && claudeWriting
        s.replyReady = running && claudeReplyReady
        for task in state.tasks where task.source == .claudeCode && !task.isIntegration {
            switch task.state {
            case .approval, .question: s.sessionsWaiting += 1
            case .working, .thinking, .searching: s.sessionsWorking += 1
            case .finished: s.sessionsDone += 1
            default: break
            }
        }
        if let plan = state.claudePlanUsage {
            let now = Date()
            if let w = plan.fiveHour, w.resetsAt > now { s.fiveHourPct = w.usedPct }
            if let w = plan.sevenDay, w.resetsAt > now { s.weekPct = w.usedPct }
        }
        return s
    }

    // MARK: - Builds

    /// Brings the island up once for a build or sync that finished since the last look. The
    /// first look only remembers what's there, so a launch doesn't replay old results; an IDE
    /// in front of you already shows its result, so it only updates the row.
    private func announce(_ app: WatchedApp, _ activities: [BuildActivity]) {
        let finished = activities.filter { $0.outcome != .running }
        guard let newest = finished.compactMap(\.endedAt).max() else { return }
        guard let seen = announced[app.id] else { announced[app.id] = newest; return }
        guard newest > seen else { return }
        announced[app.id] = newest
        guard let result = finished.first(where: { $0.endedAt == newest }),
              Date().timeIntervalSince(newest) < AppStatusLogic.buildRecency,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != app.bundleId else { return }
        appendAppLog("nb.log", "[Apps] \(app.name): \(AppStatusLogic.resultLine(result))")
        let failed = AppStatusLogic.level(result) == .error
        if AppState.shared.soundEnabled { SoundEngine.shared.play(failed ? "error" : "finish") }
        if !failed { NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy) }
        NotificationCenter.default.post(name: .hookReveal, object: nil)
    }

    private func readAndroidStudio() {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Google")
        let logs = ((try? fm.contentsOfDirectory(atPath: base.path)) ?? [])
            .filter { $0.hasPrefix("AndroidStudio") }
            .map { base.appendingPathComponent($0).appendingPathComponent("idea.log").path }
            .compactMap { path -> (String, Date, UInt64)? in
                guard let a = try? fm.attributesOfItem(atPath: path),
                      let m = a[.modificationDate] as? Date, let size = a[.size] as? UInt64 else { return nil }
                return (path, m, size)
            }
        guard let (path, _, size) = logs.max(by: { $0.1 < $1.1 }) else { return }
        if path != studioLogPath || size < studioLogOffset {   // another version, or the log rotated
            studioLogPath = path
            studioLogOffset = 0
            studioLog = AndroidStudioLogState()
        }
        guard size > studioLogOffset, let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }
        // First look: the last 2 MB are plenty to find the latest build and sync.
        let firstLook = studioLogOffset == 0
        let start = firstLook ? (size > 2_000_000 ? size - 2_000_000 : 0) : studioLogOffset
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        // Only whole lines: a line still being written is read next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let chunk = data[data.startIndex...lastNewline]
        studioLogOffset = start + UInt64(chunk.count)
        var text = String(decoding: chunk, as: UTF8.self)
        if firstLook && start > 0, let nl = text.firstIndex(of: "\n") {
            // The first look starts mid-line: skip to the first full line.
            text = String(text[text.index(after: nl)...])
        }
        text.enumerateLines { line, _ in AndroidStudioLog.apply(line, to: &self.studioLog) }
    }

    private func readXcode() -> BuildActivity? {
        let fm = FileManager.default
        let custom = UserDefaults(suiteName: "com.apple.dt.Xcode")?.string(forKey: "IDECustomDerivedDataLocation")
        let root = custom.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var newest: BuildActivity?
        for dir in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            for sub in ["Logs/Build", "Logs/Test"] {
                let path = root.appendingPathComponent(dir).appendingPathComponent(sub)
                    .appendingPathComponent("LogStoreManifest.plist").path
                guard let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { continue }
                let latest: BuildActivity?
                if let cached = xcodeManifests[path], cached.modified == m {
                    latest = cached.latest
                } else {
                    let plist = (try? Data(contentsOf: URL(fileURLWithPath: path)))
                        .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                    latest = plist.flatMap(XcodeBuildLog.latest(manifest:))
                    xcodeManifests[path] = (m, latest)
                }
                if let l = latest, (l.at ?? .distantPast) > (newest?.at ?? .distantPast) { newest = l }
            }
        }
        return newest
    }

    /// The pill's line, and a badge when an app newly needs you.
    private func updatePill() {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        let steps = AppStatusLogic.summary(statuses).map { [$0] } ?? []
        if state.tasks[idx].steps != steps { state.tasks[idx].steps = steps }
        let top = AppStatusLogic.topLevel(statuses)
        if top > lastTopLevel, top >= .attention {
            state.tasks[idx].pillBadge = top == .error ? .error : .approval
        } else if top < .attention, state.tasks[idx].pillBadge != nil {
            state.tasks[idx].pillBadge = nil
        }
        lastTopLevel = top
    }

    /// Bundle id → badge text, read from the Dock's items. Empty without Accessibility.
    private func dockBadges() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = Self.children(root).first(where: { Self.string($0, kAXRoleAttribute) == (kAXListRole as String) })
        else { return [:] }
        var badges: [String: String] = [:]
        for item in Self.children(list) {
            guard let label = Self.string(item, "AXStatusLabel"), !label.isEmpty,
                  let url = Self.url(item) else { continue }
            let key = url.path
            let id = bundleIdCache[key] ?? Bundle(url: url)?.bundleIdentifier
            bundleIdCache[key] = id
            if let id { badges[id] = label }
        }
        return badges
    }

    nonisolated private static func children(_ e: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
        return v as? [AXUIElement] ?? []
    }

    nonisolated private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    nonisolated private static func url(_ e: AXUIElement) -> URL? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXURLAttribute as CFString, &v) == .success else { return nil }
        return v as? URL
    }

    // MARK: - Actions

    func open(_ app: WatchedApp) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func askForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func icon(for app: WatchedApp) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
#endif
