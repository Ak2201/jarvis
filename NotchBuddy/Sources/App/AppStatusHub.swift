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
            if app.id == "claude" {
                return AppStatusLogic.claude(claudeSnapshot(running: isRunning), app: app,
                                             installed: installed, badge: badges[app.bundleId])
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
