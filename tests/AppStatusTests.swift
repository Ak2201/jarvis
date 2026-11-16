import Foundation

@main
enum AppStatusTests {
    static var failures = 0

    static func check(_ label: String, _ got: String?, _ expected: String?) {
        if got == expected { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)\n    got:      \(String(describing: got))\n    expected: \(String(describing: expected))")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
    }

    static let claudeApp = WatchedApps.all[0]
    static func claude(_ s: ClaudeSnapshot, badge: String? = nil) -> AppStatus {
        AppStatusLogic.claude(s, app: claudeApp, installed: true, badge: badge)
    }

    static func main() {
        print("Order")
        check("Claude comes first", WatchedApps.all.first?.id, "claude")
        check("six apps", String(WatchedApps.all.count), "6")

        print("Claude headline")
        var s = ClaudeSnapshot()
        check("closed", claude(s).headline, "Not running")
        checkTrue("closed is off", claude(s).level == .off)
        s.desktopRunning = true
        check("open", claude(s).headline, "Open")
        s.replyReady = true
        check("reply ready", claude(s).headline, "Reply ready")
        checkTrue("reply ready is done", claude(s).level == .done)
        s.sessionsWorking = 2
        check("sessions working beat a ready reply", claude(s).headline, "2 sessions working")
        check("the ready reply moves to a line", claude(s).lines.first, "Claude app: reply ready")
        s.desktopWriting = true
        check("writing", claude(s).headline, "Writing a reply")
        s.sessionsWaiting = 1
        check("waiting beats everything", claude(s).headline, "1 session waiting for you")
        checkTrue("waiting is attention", claude(s).level == .attention)
        checkTrue("Claude Code line lists the counts",
                  claude(s).lines.contains("Claude Code: 1 waiting · 2 working"))

        print("Claude extras")
        var p = ClaudeSnapshot(desktopRunning: true)
        p.fiveHourPct = 41.6; p.weekPct = 12
        check("plan line", claude(p).lines.first, "Plan: 42% of 5 h · 12% this week")
        check("badge as headline", claude(ClaudeSnapshot(desktopRunning: true), badge: "3").headline, "3 notifications")
        checkTrue("badge headline isn't repeated",
                  !claude(ClaudeSnapshot(desktopRunning: true), badge: "3").lines.contains("3 notifications"))
        check("badge as a line under a busier headline",
              claude(ClaudeSnapshot(desktopRunning: true, sessionsWorking: 1), badge: "2").lines.last, "2 notifications")

        print("Other apps")
        let arc = WatchedApps.all.first { $0.id == "arc" }!
        check("running", AppStatusLogic.generic(app: arc, installed: true, running: true, badge: nil).headline, "Open")
        check("badge", AppStatusLogic.generic(app: arc, installed: true, running: true, badge: "1").headline, "1 notification")
        check("dot badge", AppStatusLogic.generic(app: arc, installed: true, running: true, badge: "•").headline, "New notifications")
        check("99+ badge", AppStatusLogic.badgeLine("99+"), "99+ notifications")
        check("closed app has no badge", AppStatusLogic.generic(app: arc, installed: true, running: false, badge: "4").badge, nil)

        print("Summary")
        let xcode = WatchedApps.all.first { $0.id == "xcode" }!
        let quiet = [claude(ClaudeSnapshot()),
                     AppStatusLogic.generic(app: xcode, installed: true, running: false, badge: nil)]
        check("nothing open", AppStatusLogic.summary(quiet), nil)
        let open = [claude(ClaudeSnapshot(desktopRunning: true)),
                    AppStatusLogic.generic(app: xcode, installed: true, running: true, badge: nil)]
        check("only open apps", AppStatusLogic.summary(open), "2 apps open")
        let tie = [claude(ClaudeSnapshot(desktopRunning: true), badge: "1"),
                   AppStatusLogic.generic(app: arc, installed: true, running: true, badge: "5")]
        check("Claude wins a tie", AppStatusLogic.summary(tie), "Claude · 1 notification")
        let arcFirst = [claude(ClaudeSnapshot(desktopRunning: true)),
                        AppStatusLogic.generic(app: arc, installed: true, running: true, badge: "5")]
        check("a more urgent app wins", AppStatusLogic.summary(arcFirst), "Arc · 5 notifications")
        let notInstalled = [AppStatusLogic.generic(app: arc, installed: false, running: true, badge: "5")]
        check("apps that aren't installed are left out", AppStatusLogic.summary(notInstalled), nil)

        print(failures == 0 ? "\nAll tests passed." : "\n\(failures) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
