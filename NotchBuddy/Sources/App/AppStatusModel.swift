import Foundation

// The Apps pill: what your main apps are doing, in one place. This file is the pure part
// (Foundation only, tested in tests/AppStatusTests.swift); AppStatusHub reads the Mac and
// fills these models in.

/// One app the Apps pill keeps an eye on.
struct WatchedApp: Equatable {
    let id: String
    let name: String
    let bundleId: String
}

enum WatchedApps {
    /// In priority order: Claude first. The card lists them this way, and when two apps are
    /// equally urgent the pill's line speaks of the one higher up.
    static let all: [WatchedApp] = [
        .init(id: "claude",         name: "Claude",          bundleId: "com.anthropic.claudefordesktop"),
        .init(id: "xcode",          name: "Xcode",           bundleId: "com.apple.dt.Xcode"),
        .init(id: "android-studio", name: "Android Studio",  bundleId: "com.google.android.studio"),
        .init(id: "chrome",         name: "Chrome",          bundleId: "com.google.Chrome"),
        .init(id: "arc",            name: "Arc",             bundleId: "company.thebrowser.Browser"),
        .init(id: "resolve",        name: "DaVinci Resolve", bundleId: "com.blackmagic-design.DaVinciResolve"),
    ]
}

/// How much an app wants you, least to most.
enum AppLevel: Int, Comparable {
    case off, idle, done, working, attention, error
    static func < (a: AppLevel, b: AppLevel) -> Bool { a.rawValue < b.rawValue }
}

struct AppStatus: Identifiable, Equatable {
    let app: WatchedApp
    var id: String { app.id }
    var installed: Bool
    var running: Bool
    /// The app's Dock badge as macOS shows it ("3", "99+", "•"), nil when there is none.
    var badge: String?
    var level: AppLevel
    var headline: String
    /// Extra lines under the headline (Claude has several sources).
    var lines: [String] = []
}

/// Everything Jarvis knows about Claude: the Claude app, Claude Code sessions, the plan.
struct ClaudeSnapshot: Equatable {
    var desktopRunning = false
    /// The Claude app is writing a reply (its stop button is on screen).
    var desktopWriting = false
    /// A reply finished while you were in another app, and you haven't gone back yet.
    var replyReady = false
    var sessionsWorking = 0
    /// Sessions waiting on a permission or a question.
    var sessionsWaiting = 0
    var sessionsDone = 0
    /// Plan usage in percent, when the plan gauge is on.
    var fiveHourPct: Double?
    var weekPct: Double?
}

enum AppStatusLogic {

    static func claude(_ s: ClaudeSnapshot, app: WatchedApp, installed: Bool, badge: String?) -> AppStatus {
        let level: AppLevel
        let headline: String
        if s.sessionsWaiting > 0 {
            level = .attention
            headline = count(s.sessionsWaiting, one: L("apps.claude.waiting-one", "1 session waiting for you"),
                             many: L("apps.claude.waiting-many", "%lld sessions waiting for you"))
        } else if s.desktopWriting {
            level = .working
            headline = L("apps.claude.writing", "Writing a reply")
        } else if s.sessionsWorking > 0 {
            level = .working
            headline = count(s.sessionsWorking, one: L("apps.claude.working-one", "1 session working"),
                             many: L("apps.claude.working-many", "%lld sessions working"))
        } else if s.replyReady {
            level = .done
            headline = L("apps.claude.reply-ready", "Reply ready")
        } else if s.sessionsDone > 0 {
            level = .done
            headline = count(s.sessionsDone, one: L("apps.claude.done-one", "1 session done"),
                             many: L("apps.claude.done-many", "%lld sessions done"))
        } else if let badge, s.desktopRunning {
            level = .attention
            headline = badgeLine(badge)
        } else if s.desktopRunning {
            level = .idle
            headline = L("apps.running", "Open")
        } else {
            level = .off
            headline = L("apps.not-running", "Not running")
        }

        var lines: [String] = []
        // The Claude app, when the headline isn't already about it.
        if s.desktopWriting && s.sessionsWaiting > 0 {
            lines.append(L("apps.claude.app-writing", "Claude app: writing a reply"))
        } else if s.replyReady && (s.sessionsWaiting > 0 || s.sessionsWorking > 0) {
            lines.append(L("apps.claude.app-reply-ready", "Claude app: reply ready"))
        }
        // Claude Code, when there is more than the headline says.
        let parts = [
            s.sessionsWaiting > 0 ? String(format: L("apps.claude.n-waiting", "%lld waiting"), s.sessionsWaiting) : nil,
            s.sessionsWorking > 0 ? String(format: L("apps.claude.n-working", "%lld working"), s.sessionsWorking) : nil,
            s.sessionsDone > 0 ? String(format: L("apps.claude.n-done", "%lld done"), s.sessionsDone) : nil,
        ].compactMap { $0 }
        if parts.count > 1 {
            lines.append(String(format: L("apps.claude.code-line", "Claude Code: %@"), parts.joined(separator: " · ")))
        }
        if let line = planLine(fiveHour: s.fiveHourPct, week: s.weekPct) { lines.append(line) }
        if let badge, level != .attention || s.sessionsWaiting > 0, s.desktopRunning {
            lines.append(badgeLine(badge))
        }
        return AppStatus(app: app, installed: installed, running: s.desktopRunning, badge: badge,
                         level: level, headline: headline, lines: lines)
    }

    /// An app Jarvis only sees from the outside: running or not, and its Dock badge.
    static func generic(app: WatchedApp, installed: Bool, running: Bool, badge: String?) -> AppStatus {
        let level: AppLevel
        let headline: String
        if running, let badge {
            level = .attention
            headline = badgeLine(badge)
        } else if running {
            level = .idle
            headline = L("apps.running", "Open")
        } else {
            level = .off
            headline = L("apps.not-running", "Not running")
        }
        return AppStatus(app: app, installed: installed, running: running, badge: running ? badge : nil,
                         level: level, headline: headline)
    }

    /// The line the pill shows: the most urgent app, Claude first among equals. Nil when
    /// nothing is open.
    static func summary(_ statuses: [AppStatus]) -> String? {
        let shown = statuses.filter { $0.installed && $0.level > .off }
        guard let top = shown.enumerated().max(by: { a, b in
            a.element.level != b.element.level ? a.element.level < b.element.level : a.offset > b.offset
        })?.element else { return nil }
        if top.level == .idle {
            return count(shown.count, one: L("apps.one-open", "1 app open"), many: L("apps.many-open", "%lld apps open"))
        }
        return "\(top.app.name) · \(top.headline)"
    }

    /// The most urgent level among the apps, for the pill's badge.
    static func topLevel(_ statuses: [AppStatus]) -> AppLevel {
        statuses.filter(\.installed).map(\.level).max() ?? .off
    }

    /// "3 notifications" for "3", "New notifications" for "•" or any other mark.
    static func badgeLine(_ badge: String) -> String {
        if let n = Int(badge.trimmingCharacters(in: .whitespaces)) {
            return count(n, one: L("apps.badge-one", "1 notification"), many: L("apps.badge-many", "%lld notifications"))
        }
        if badge.hasSuffix("+"), Int(badge.dropLast()) != nil {
            return String(format: L("apps.badge-many-text", "%@ notifications"), badge)
        }
        return L("apps.badge-some", "New notifications")
    }

    static func planLine(fiveHour: Double?, week: Double?) -> String? {
        switch (fiveHour, week) {
        case let (f?, w?):
            return String(format: L("apps.claude.plan-both", "Plan: %lld%% of 5 h · %lld%% this week"),
                          Int(f.rounded()), Int(w.rounded()))
        case let (f?, nil):
            return String(format: L("apps.claude.plan-5h", "Plan: %lld%% of 5 h"), Int(f.rounded()))
        case let (nil, w?):
            return String(format: L("apps.claude.plan-week", "Plan: %lld%% this week"), Int(w.rounded()))
        default:
            return nil
        }
    }

    private static func count(_ n: Int, one: String, many: String) -> String {
        n == 1 ? one : String(format: many, n)
    }

    private static func L(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value)
    }
}
