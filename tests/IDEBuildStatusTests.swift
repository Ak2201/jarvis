import Foundation

// Lines copied from a real Android Studio 2026.1 idea.log and a real Xcode LogStoreManifest.plist.

@main
enum IDEBuildStatusTests {
    static var failures = 0
    static func check(_ label: String, _ got: String?, _ expected: String?) {
        if got == expected { print("  ✓ \(label)") }
        else { print("  ✗ \(label)\n    got:      \(String(describing: got))\n    expected: \(String(describing: expected))"); failures += 1 }
    }
    static func checkTrue(_ label: String, _ v: Bool) { if v { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 } }

    static let buildStart = "2026-11-03 16:48:54,733 [1223027463]   INFO - #com.android.tools.idea.gradle.project.build.invoker.GradleBuildInvoker - About to execute Gradle tasks: [:zohooneuser:assembleDebug, :zohooneuser:assembleDebugUnitTest, :zohooneuser:assembleDebugAndroidTest]"
    static let buildDone = "2026-11-03 16:49:58,859 [1223091589]   INFO - #com.android.tools.idea.gradle.project.build.invoker.GradleBuildInvoker - Gradle build finished in 1 m 4 s 109 ms"
    static let buildFailed = "2026-10-14 16:59:17,354 [193511592]   INFO - #com.android.tools.idea.gradle.project.build.invoker.GradleBuildInvoker - Gradle build failed in 888 ms"
    static let buildCancelled = "2026-10-14 16:59:22,227 [193516465]   INFO - #com.android.tools.idea.gradle.project.build.invoker.GradleBuildInvoker - Gradle build cancelled with 1 error(s) in 4 s 872 ms"
    static let syncStart = "2026-11-11 16:44:20,960 [190678459]   INFO - #com.android.tools.idea.gradle.project.sync.GradleSyncStateHolder - Started (TRIGGER_QF_APPLY_COMPATIBLE_GRADLE_JVM) sync with Gradle for project 'My zoho'."
    static let syncFailed = "2026-11-11 16:45:12,761 [190730260]   WARN - #com.android.tools.idea.gradle.project.sync.GradleSyncStateHolder - Gradle sync failed in 51 s 802 ms. Incompatible Gradle JVM version"
    static let syncDone = "2026-11-10 13:32:52,816 [92790315]   INFO - #com.android.tools.idea.gradle.project.sync.GradleSyncStateHolder - Gradle sync finished in 18 s 115 ms"
    static let noise = "2026-11-03 16:48:54,739 [1223027469]   INFO - #o.j.p.g.GradleManager - Instructing gradle to use java from /Users/x/jbr-17/Contents/Home"

    static let studio = WatchedApps.all.first { $0.id == "android-studio" }!
    static let xcodeApp = WatchedApps.all.first { $0.id == "xcode" }!

    static func main() {
        print("Android Studio log")
        var st = AndroidStudioLog.parse([buildStart, noise].joined(separator: "\n"))
        checkTrue("build started is running", st.build?.outcome == .running)
        check("task label", st.build?.label, "assembleDebug +2")
        AndroidStudioLog.apply(buildDone, to: &st)
        checkTrue("build finished", st.build?.outcome == .succeeded)
        check("build duration", st.build?.duration, "1 m 4 s 109 ms")
        check("label kept after the end", st.build?.label, "assembleDebug +2")
        AndroidStudioLog.apply(buildFailed, to: &st)
        checkTrue("build failed", st.build?.outcome == .failed(errors: nil))
        AndroidStudioLog.apply(buildCancelled, to: &st)
        checkTrue("build cancelled", st.build?.outcome == .cancelled)
        check("cancelled duration", st.build?.duration, "4 s 872 ms")

        var sy = AndroidStudioLog.parse(syncStart)
        check("sync project", sy.sync?.label, "My zoho")
        AndroidStudioLog.apply(syncFailed, to: &sy)
        checkTrue("sync failed", sy.sync?.outcome == .failed(errors: nil))
        check("sync failure reason", sy.sync?.reason, "Incompatible Gradle JVM version")
        check("sync duration", sy.sync?.duration, "51 s 802 ms")
        AndroidStudioLog.apply(syncDone, to: &sy)
        checkTrue("sync finished", sy.sync?.outcome == .succeeded)
        checkTrue("timestamp parsed", AndroidStudioLog.timestamp(buildDone) != nil)

        print("Android Studio row")
        let doneAt = AndroidStudioLog.timestamp(buildDone)!
        var ok = AndroidStudioLog.parse([buildStart, buildDone].joined(separator: "\n"))
        var row = AppStatusLogic.androidStudio(app: studio, installed: true, running: true, badge: nil, log: ok,
                                               now: doneAt.addingTimeInterval(60))
        check("recent success", row.headline, "Build succeeded in 1 m 4 s 109 ms")
        checkTrue("success is done", row.level == .done)
        check("task under it", row.lines.first, "assembleDebug +2")
        row = AppStatusLogic.androidStudio(app: studio, installed: true, running: true, badge: nil, log: ok,
                                           now: doneAt.addingTimeInterval(3 * 3600))
        check("old result is quiet", row.headline, "Open")
        checkTrue("old result is a line", row.lines.first?.hasPrefix("Build succeeded in 1 m 4 s 109 ms · assembleDebug +2") == true)

        let startAt = AndroidStudioLog.timestamp(buildStart)!
        ok = AndroidStudioLog.parse(buildStart)
        row = AppStatusLogic.androidStudio(app: studio, installed: true, running: true, badge: nil, log: ok,
                                           now: startAt.addingTimeInterval(20))
        check("building now", row.headline, "Building assembleDebug +2…")
        checkTrue("building is working", row.level == .working)
        row = AppStatusLogic.androidStudio(app: studio, installed: true, running: false, badge: nil, log: ok,
                                           now: startAt.addingTimeInterval(20))
        check("a build can't run with Studio closed", row.headline, "Not running")

        let failAt = AndroidStudioLog.timestamp(syncFailed)!
        let bad = AndroidStudioLog.parse([syncStart, syncFailed].joined(separator: "\n"))
        row = AppStatusLogic.androidStudio(app: studio, installed: true, running: true, badge: nil, log: bad,
                                           now: failAt.addingTimeInterval(30))
        check("sync failed headline", row.headline, "Sync failed")
        checkTrue("sync failure is an error", row.level == .error)
        checkTrue("reason shown", row.lines.contains("Incompatible Gradle JVM version"))
        checkTrue("project shown", row.lines.contains("My zoho"))

        print("Xcode manifest")
        let manifest: [String: Any] = ["logs": [
            "A": ["primaryObservable": ["highLevelStatus": "S", "totalNumberOfErrors": 0, "totalNumberOfWarnings": 0],
                  "timeStartedRecording": 816514000.0, "timeStoppedRecording": 816514010.0,
                  "domainType": "Xcode.IDEActivityLogDomainType.BuildLog", "schemeIdentifier-schemeName": "NotchBuddy",
                  "title": "Building project NotchBuddy with scheme NotchBuddy and configuration Debug"],
            "B": ["primaryObservable": ["highLevelStatus": "E", "totalNumberOfErrors": 1, "totalNumberOfWarnings": 1,
                                        "totalNumberOfAnalyzerIssues": 0, "totalNumberOfTestFailures": 0],
                  "timeStartedRecording": 816514086.390739, "timeStoppedRecording": 816514090.957883,
                  "domainType": "Xcode.IDEActivityLogDomainType.BuildLog", "schemeIdentifier-schemeName": "NotchBuddy",
                  "title": "Building project NotchBuddy with scheme NotchBuddy and configuration Debug"],
        ]]
        let latest = XcodeBuildLog.latest(manifest: manifest)
        checkTrue("latest entry wins", latest?.outcome == .failed(errors: 1))
        check("scheme", latest?.label, "NotchBuddy")
        let stop = Date(timeIntervalSinceReferenceDate: 816514090.957883)
        row = AppStatusLogic.xcode(app: xcodeApp, installed: true, running: true, badge: nil, latest: latest,
                                   now: stop.addingTimeInterval(10))
        check("xcode failed headline", row.headline, "Build failed · 1 error")
        checkTrue("xcode failure is an error", row.level == .error)
        let warn = XcodeBuildLog.activity(["primaryObservable": ["highLevelStatus": "W", "totalNumberOfWarnings": 3],
                                           "domainType": "Xcode.IDEActivityLogDomainType.BuildLog"])
        check("warnings", warn.map(AppStatusLogic.resultLine), "Build succeeded · 3 warnings")
        let tests = XcodeBuildLog.activity(["primaryObservable": ["highLevelStatus": "E", "totalNumberOfTestFailures": 2],
                                            "domainType": "Xcode.IDEActivityLogDomainType.TestLog"])
        check("test failures", tests.map(AppStatusLogic.resultLine), "2 tests failed")
        check("empty manifest", XcodeBuildLog.latest(manifest: [:]).map(AppStatusLogic.resultLine), nil)

        print(failures == 0 ? "\nAll tests passed." : "\n\(failures) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
