import Foundation

// Build status for the Apps pill: Android Studio's Gradle builds and syncs (from its idea.log)
// and Xcode's builds and tests (from DerivedData's LogStoreManifest.plist). Foundation only,
// tested in tests/IDEBuildStatusTests.swift with lines copied from real logs; AppStatusHub
// finds the files and feeds them in.

/// One build or sync, running or done.
struct BuildActivity: Equatable {
    enum Kind: Equatable { case build, sync, test }
    enum Outcome: Equatable { case running, succeeded, warnings(Int), failed(errors: Int?), cancelled }
    var kind: Kind
    var outcome: Outcome
    var startedAt: Date?
    var endedAt: Date?
    /// What ran: "assembleDebug", the project for a sync, the Xcode scheme.
    var label: String?
    /// Why a sync failed, as Android Studio says it.
    var reason: String?
    /// "1 m 4 s" as Android Studio wrote it.
    var duration: String?

    var at: Date? { endedAt ?? startedAt }
}

// MARK: - Android Studio

/// What idea.log says so far: the latest build and the latest sync.
struct AndroidStudioLogState: Equatable {
    var build: BuildActivity?
    var sync: BuildActivity?
}

enum AndroidStudioLog {

    /// Updates the state with one line of idea.log. Lines that aren't about builds or syncs
    /// are ignored.
    static func apply(_ line: String, to state: inout AndroidStudioLogState) {
        guard line.contains("GradleBuildInvoker") || line.contains("GradleSyncStateHolder") else { return }
        let date = timestamp(line)
        // The message follows the logger's name: "…GradleBuildInvoker - Gradle build finished in …"
        guard let message = (line.range(of: "GradleBuildInvoker - ") ?? line.range(of: "GradleSyncStateHolder - "))
            .map({ String(line[$0.upperBound...]) }) else { return }

        if line.contains("GradleBuildInvoker") {
            if message.hasPrefix("About to execute Gradle tasks:") {
                state.build = BuildActivity(kind: .build, outcome: .running, startedAt: date,
                                            label: taskLabel(message))
            } else if let d = after(message, "Gradle build finished in ") {
                end(&state.build, .build, .succeeded, at: date, duration: d)
            } else if let d = after(message, "Gradle build failed in ") {
                end(&state.build, .build, .failed(errors: nil), at: date, duration: d)
            } else if message.hasPrefix("Gradle build cancelled") {
                end(&state.build, .build, .cancelled, at: date,
                    duration: message.range(of: " in ").map { String(message[$0.upperBound...]) })
            }
        } else {
            if message.hasPrefix("Started ("), message.contains("sync with Gradle") {
                state.sync = BuildActivity(kind: .sync, outcome: .running, startedAt: date,
                                           label: quoted(message))
            } else if let d = after(message, "Gradle sync finished in ") {
                end(&state.sync, .sync, .succeeded, at: date, duration: d)
            } else if let rest = after(message, "Gradle sync failed in ") {
                // "51 s 802 ms. Incompatible Gradle JVM version"
                let parts = rest.components(separatedBy: ". ")
                end(&state.sync, .sync, .failed(errors: nil), at: date, duration: parts.first)
                if parts.count > 1 {
                    state.sync?.reason = parts.dropFirst().joined(separator: ". ")
                        .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
                }
            }
        }
    }

    static func parse(_ text: String) -> AndroidStudioLogState {
        var state = AndroidStudioLogState()
        text.enumerateLines { line, _ in apply(line, to: &state) }
        return state
    }

    private static func end(_ activity: inout BuildActivity?, _ kind: BuildActivity.Kind,
                            _ outcome: BuildActivity.Outcome, at date: Date?, duration: String?) {
        var a = activity ?? BuildActivity(kind: kind, outcome: outcome)
        a.outcome = outcome
        a.endedAt = date
        a.duration = duration?.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        activity = a
    }

    /// "2026-11-03 16:49:58,859 [1223091589]   INFO - …" → that moment, local time.
    static func timestamp(_ line: String) -> Date? {
        guard line.count >= 23 else { return nil }
        return formatter.date(from: String(line.prefix(23)))
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
        return f
    }()

    private static func after(_ s: String, _ prefix: String) -> String? {
        s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : nil
    }

    private static func quoted(_ s: String) -> String? {
        guard let a = s.firstIndex(of: "'"), let b = s[s.index(after: a)...].firstIndex(of: "'") else { return nil }
        return String(s[s.index(after: a)..<b])
    }

    /// "[:zohooneuser:assembleDebug, :zohooneuser:assembleDebugUnitTest]" → "assembleDebug",
    /// with "+2" when there are more tasks.
    private static func taskLabel(_ message: String) -> String? {
        guard let open = message.firstIndex(of: "["), let close = message.lastIndex(of: "]"), open < close else { return nil }
        let tasks = message[message.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = tasks.first else { return nil }
        let name = first.split(separator: ":").last.map(String.init) ?? first
        return tasks.count > 1 ? "\(name) +\(tasks.count - 1)" : name
    }
}

// MARK: - Xcode

enum XcodeBuildLog {

    /// The latest build or test in a LogStoreManifest.plist (already decoded), nil when empty.
    static func latest(manifest: [String: Any]) -> BuildActivity? {
        guard let logs = manifest["logs"] as? [String: Any] else { return nil }
        let entries = logs.values.compactMap { $0 as? [String: Any] }
        guard let e = entries.max(by: { stopped($0) < stopped($1) }) else { return nil }
        return activity(e)
    }

    static func activity(_ e: [String: Any]) -> BuildActivity? {
        guard let obs = e["primaryObservable"] as? [String: Any] else { return nil }
        let errors = obs["totalNumberOfErrors"] as? Int ?? 0
        let warnings = obs["totalNumberOfWarnings"] as? Int ?? 0
        let testFailures = obs["totalNumberOfTestFailures"] as? Int ?? 0
        let status = obs["highLevelStatus"] as? String ?? ""
        let domain = e["domainType"] as? String ?? ""
        let isTest = domain.contains("Test") || (e["title"] as? String ?? "").hasPrefix("Test")
        let outcome: BuildActivity.Outcome
        if isTest && testFailures > 0 {
            outcome = .failed(errors: testFailures)
        } else if status == "E" || errors > 0 {
            outcome = .failed(errors: errors)
        } else if status == "W" || warnings > 0 {
            outcome = .warnings(warnings)
        } else {
            outcome = .succeeded
        }
        let start = (e["timeStartedRecording"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) }
        let stop = (e["timeStoppedRecording"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) }
        return BuildActivity(kind: isTest ? .test : .build, outcome: outcome, startedAt: start, endedAt: stop,
                             label: e["schemeIdentifier-schemeName"] as? String)
    }

    private static func stopped(_ e: [String: Any]) -> Double { e["timeStoppedRecording"] as? Double ?? 0 }
}

// MARK: - Status rows

extension AppStatusLogic {
    /// A result stays the headline (and the app's level) this long; after that it becomes a
    /// quiet "Last build" line, so yesterday's failure doesn't keep shouting.
    static let buildRecency: TimeInterval = 30 * 60
    /// A build or sync with no end line after this long is treated as lost (Studio quit).
    static let runningTimeout: TimeInterval = 60 * 60

    static func androidStudio(app: WatchedApp, installed: Bool, running: Bool, badge: String?,
                              log: AndroidStudioLogState, now: Date = Date()) -> AppStatus {
        let activities = [log.build, log.sync].compactMap { $0 }
        return ide(app: app, installed: installed, running: running, badge: badge,
                   activities: activities, now: now)
    }

    static func xcode(app: WatchedApp, installed: Bool, running: Bool, badge: String?,
                      latest: BuildActivity?, now: Date = Date()) -> AppStatus {
        ide(app: app, installed: installed, running: running, badge: badge,
            activities: latest.map { [$0] } ?? [], now: now)
    }

    private static func ide(app: WatchedApp, installed: Bool, running: Bool, badge: String?,
                            activities: [BuildActivity], now: Date) -> AppStatus {
        var status = generic(app: app, installed: installed, running: running, badge: badge)
        let live = activities.filter {
            $0.outcome == .running && running && now.timeIntervalSince($0.startedAt ?? .distantPast) < runningTimeout
        }
        let done = activities.filter { $0.outcome != .running }.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }

        if let a = live.first {
            status.level = .working
            status.headline = runningLine(a)
            if let last = done.first { status.lines.append(lastLine(last)) }
            return status
        }
        guard let last = done.first else { return status }
        let recent = now.timeIntervalSince(last.at ?? .distantPast) < buildRecency
        if recent {
            status.level = level(last)
            status.headline = resultLine(last)
            if let label = last.label { status.lines.append(label) }
            if let reason = last.reason { status.lines.append(reason) }
            if let other = done.dropFirst().first { status.lines.append(lastLine(other)) }
        } else {
            status.lines.append(lastLine(last))
        }
        return status
    }

    static func level(_ a: BuildActivity) -> AppLevel {
        switch a.outcome {
        case .failed: return .error
        case .cancelled: return .idle
        case .running: return .working
        case .succeeded, .warnings: return .done
        }
    }

    static func runningLine(_ a: BuildActivity) -> String {
        switch a.kind {
        case .sync:
            return a.label.map { String(format: L2("apps.ide.syncing-project", "Syncing %@…"), $0) }
                ?? L2("apps.ide.syncing", "Gradle sync…")
        case .build, .test:
            return a.label.map { String(format: L2("apps.ide.building-label", "Building %@…"), $0) }
                ?? L2("apps.ide.building", "Building…")
        }
    }

    /// The headline for a finished build, sync or test run.
    static func resultLine(_ a: BuildActivity) -> String {
        let what: String
        switch (a.kind, a.outcome) {
        case (.sync, .failed):
            what = L2("apps.ide.sync-failed", "Sync failed")
        case (.sync, _):
            what = L2("apps.ide.sync-finished", "Sync finished")
        case (.test, .failed(let n)):
            what = n.map { $0 == 1 ? L2("apps.ide.test-failed-one", "1 test failed")
                                   : String(format: L2("apps.ide.tests-failed-many", "%lld tests failed"), $0) }
                ?? L2("apps.ide.tests-failed", "Tests failed")
        case (.test, _):
            what = L2("apps.ide.tests-passed", "Tests passed")
        case (.build, .failed(let n)):
            if let n, n > 0 {
                what = n == 1 ? L2("apps.ide.build-failed-one", "Build failed · 1 error")
                              : String(format: L2("apps.ide.build-failed-many", "Build failed · %lld errors"), n)
            } else {
                what = L2("apps.ide.build-failed", "Build failed")
            }
        case (.build, .warnings(let n)):
            what = n == 1 ? L2("apps.ide.build-warning-one", "Build succeeded · 1 warning")
                          : String(format: L2("apps.ide.build-warnings-many", "Build succeeded · %lld warnings"), n)
        case (.build, .cancelled):
            what = L2("apps.ide.build-cancelled", "Build cancelled")
        case (.build, _):
            what = L2("apps.ide.build-succeeded", "Build succeeded")
        }
        if let d = a.duration, case .succeeded = a.outcome {
            return String(format: L2("apps.ide.result-in", "%1$@ in %2$@"), what, d)
        }
        return what
    }

    /// "Last build: Build failed · 14:02" for a result that's no longer the headline.
    static func lastLine(_ a: BuildActivity) -> String {
        var line = resultLine(a)
        if let label = a.label, a.kind != .sync { line += " · \(label)" }
        if let at = a.at {
            let f = DateFormatter()
            f.dateStyle = Calendar.current.isDateInToday(at) ? .none : .short
            f.timeStyle = .short
            line += " · " + f.string(from: at)
        }
        return line
    }

    fileprivate static func L2(_ key: StaticString, _ value: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: value)
    }
}
