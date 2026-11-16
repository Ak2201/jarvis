# Integration paths — Jarvis as one place for everything new

The goal: Jarvis sits on screen (or hides until something new arrives), and **anything new in
your apps — Claude, WhatsApp, Gmail, Chrome, Arc, Xcode, Android Studio, DaVinci Resolve —
shows up in the island**. This document is the plan for building each source: where its data
comes from, how to read it, what permission it needs, and how it reaches the island.

macOS only for now (`NotchBuddy/`, GitHub build — everything here needs `#if !APPSTORE`, the
App Store build is sandboxed).

Status legend: ✅ built · 🟡 partly built · ⬜ to do

| # | Source | Status | Data comes from | Permission |
|---|--------|--------|-----------------|------------|
| 0 | Island always visible / pop up on new | ✅ | Settings → General → Behavior | — |
| 1 | Claude (app, Claude Code, plan) | ✅ | Hooks, Accessibility, plan gauge | Accessibility |
| 2 | Dock badges for every app | ✅ | Dock's Accessibility tree | Accessibility |
| 3 | macOS notifications feed (all apps) | ⬜ | Notification Center database | Full Disk Access |
| 4 | WhatsApp | 🟡 | WhatsApp pill (local gateway) / Dock badge / feed | — / Accessibility / FDA |
| 5 | Gmail | 🟡 | Apple Mail pill / Gmail API / feed | Automation / OAuth / FDA |
| 6 | Xcode | ⬜ | DerivedData build logs | — |
| 7 | Android Studio | ⬜ | `idea.log` | — |
| 8 | DaVinci Resolve | ⬜ | Resolve log / scripting API | — |
| 9 | Chrome and Arc | 🟡 | Dock badge ✅, web notifications through #3 | Accessibility / FDA |

**Suggested order:** 3 (it unlocks WhatsApp, Gmail, Chrome, Arc and most other apps at once) →
6 → 7 → 5 (Gmail API) → 8.

---

## How a source reaches the island (read this first)

Everything goes through the **Apps pill** (`integration_apps`):

- `NotchBuddy/Sources/App/AppStatusModel.swift` — pure logic: `WatchedApps.all` (the apps, in
  priority order, Claude first), `AppStatus` (one row), `AppStatusLogic` (headlines, the pill's
  summary line, urgency). Tested by `scripts/test-app-status.sh`. **Put new parsing here** so it
  can be tested without AppKit.
- `NotchBuddy/Sources/App/AppStatusHub.swift` — reads the Mac every 3 s while the pill is on
  (running apps, Dock badges, Claude), publishes `statuses`, and updates the pill's task.
- `NotchBuddy/Sources/App/AppStatusViews.swift` — the card (one row per app) and the Settings section.

To add a source:

1. Add the app to `WatchedApps.all` if it isn't there (id, name, bundle id).
2. Write a reader that produces a small value (e.g. `XcodeBuild(status:errors:warnings:finishedAt:)`)
   in a new file, and a pure function in `AppStatusLogic` that turns it into an `AppStatus`
   (level, headline, lines). Add tests to `tests/AppStatusTests.swift`.
3. In `AppStatusHub.refresh()`, use it for that app instead of `AppStatusLogic.generic`.
   Prefer **file watching** (`DispatchSource.makeFileSystemObjectSource` or FSEvents) over
   polling when the data is a file, and do nothing while the pill is off (performance rule:
   0 % CPU when idle).
4. **Popping up:** when something *new* arrives (not on every refresh), make the island show it:
   ```swift
   NotificationCenter.default.post(name: .hookReveal, object: nil)      // show the compact island
   if AppState.shared.soundEnabled { SoundEngine.shared.play("finish") } // or "error", "approval"
   ```
   The hub already sets the pill's badge when an app's level rises to `.attention`/`.error`
   (`updatePill()`). Keep a "last seen" marker per source (date or id) so a restart doesn't
   replay old items.
5. Strings: `String(localized: "apps.<source>.<thing>", defaultValue: "…")`, then add the key
   to `NotchBuddy/Resources/Localizable.xcstrings` in all 16 languages
   (`python3 scripts/test-localization.py` must pass — it requires zh-Hant for every key).

**Privacy rules (from CLAUDE.md, keep them):** no telemetry; network only to services the user
configured; secrets in the Keychain; never send anything or act without an explicit click.
Showing a notification's title/sender is fine; don't store message bodies on disk.

---

## 0. Island always visible ✅

- Settings → General → Behavior → **Always show the island** (`AppState.alwaysVisible`,
  `IslandStateMachine.alwaysVisible`). On: the compact island never hides on its own. Off
  (default): it hides after "Hide after N min" and comes back on `.hookReveal`, i.e. when
  something new arrives.
- Possible next step: a third mode "only when something is waiting" (hide right away when no
  pill has a badge). That's `IslandStateMachine.schedulePetitHide()` with a delay of ~5 s when
  `AppState.tasks.allSatisfy { $0.pillBadge == nil }`.

## 1. Claude ✅

What the Apps pill shows for Claude today, in order of urgency:

- Claude Code sessions waiting for you (permission or question), working, done — from the hook
  server's tasks (`AppState.tasks` with `source == .claudeCode`).
- The Claude app writing a reply / reply ready — `ClaudeDesktopChatWatcher` (Accessibility: it
  looks for the "Stop response" button when you leave Claude). Posts
  `ClaudeDesktopChatWatcher.replyNotification`.
- Plan usage (5-hour and weekly) — `AppState.claudePlanUsage`, when Settings → Agents → Plan
  usage is on.
- Claude's Dock badge.

Next: the Claude app's own notifications come for free with source #3.

## 2. Dock badges ✅

`AppStatusHub.dockBadges()` reads the Dock through Accessibility: Dock process →
`AXList` → each `AXDockItem` has `AXURL` (the .app, mapped to a bundle id) and `AXStatusLabel`
(the red badge text: "3", "99+", "•"). Works for any app in the Dock, including ones only
kept in the Dock while running. Cheap (one tree walk of ~30 items).

Limits: an app must be in the Dock; a badge is a count, not content. Source #3 gives content.

## 3. macOS notifications feed ⬜ — the big one

Every banner an app shows (Chrome and Arc web notifications — Gmail, WhatsApp Web, Slack —,
WhatsApp desktop, Claude, Mail, Messages, Telegram…) is stored by macOS in a SQLite database:

- Path: `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (plus `db-wal`, `db-shm`).
  **Verify on macOS 26** — the location and schema have moved between releases; on this Mac
  (macOS 26.7) the folder exists and is protected by TCC.
- Permission: **Full Disk Access** for Jarvis (System Settings → Privacy & Security → Full Disk
  Access). There is no prompt API; detect it by trying to open the file, and show a button that
  opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
- Schema (Sonoma/Sequoia, check on 26): table `app` (`app_id`, `identifier` = bundle id), table
  `record` (`rec_id`, `app_id`, `delivered_date` — Core Data timestamp, seconds since
  2001-01-01 —, `presented`, `data` — a binary plist). In `data`: `req` → `titl` (title),
  `subt` (subtitle), `body`; `app` (bundle id). Decode with `PropertyListSerialization`.
- Reading: open **read-only** with `sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)`
  (link `libsqlite3.tbd`, no third-party dependency). Query only rows newer than the last
  `rec_id` you saw:
  ```sql
  SELECT r.rec_id, a.identifier, r.delivered_date, r.data
  FROM record r JOIN app a ON a.app_id = r.app_id
  WHERE r.rec_id > ? ORDER BY r.rec_id;
  ```
  Watch `db-wal` with a file-system source and re-query on change (no polling).
- Output: a `NotificationItem(app bundle id, title, subtitle, body, date)`. Map bundle ids to
  `WatchedApps` (and add more apps: WhatsApp `net.whatsapp.WhatsApp`, Messages
  `com.apple.MobileSMS`, Slack `com.tinyspeck.slackmacgap`, Telegram `ru.keepcoder.Telegram`).
  For Chrome/Arc, the title is usually the site ("Gmail", "WhatsApp") — show it as the source.
- UI: in the card, under each app, its last 1–3 notifications (title · time). In the pill line:
  "Arc · Gmail: New message from Ana". Pop up (`.hookReveal`) once per new item. A setting to
  choose which apps may pop up.
- Privacy: keep only the last few items in memory; never write bodies to disk; a switch to show
  titles only.

## 4. WhatsApp 🟡

Three paths, pick by how much you need:

1. **Already in Jarvis: the WhatsApp pill** (`integration_whatsapp`,
   `WhatsAppController.swift`, `WhatsAppGateway.swift`, Settings → Integrations → WhatsApp). It
   runs a local gateway (GOWA, go-whatsapp-web-multidevice) that links to your phone like
   WhatsApp Web; new messages arrive by webhook on your Mac. Full content, can reply. Turn it on
   and link with the QR code. Nothing new to build — only make its new messages also feed the
   Apps pill if wanted.
2. **WhatsApp desktop app:** add `net.whatsapp.WhatsApp` to `WatchedApps.all` → Dock badge
   (unread count) for free with #2.
3. **Notifications feed (#3):** sender and preview of each message, from WhatsApp desktop or
   WhatsApp Web in Chrome/Arc.

(The official WhatsApp Business Cloud API only works for business numbers — not for a personal
account.)

## 5. Gmail 🟡

1. **Already in Jarvis: the Mail pill** (`integration_mail`, `MailController.swift`) reads Apple
   Mail through AppleScript. Add the Gmail account to Apple Mail (System Settings → Internet
   Accounts → Google) and Gmail shows up there: unread, search, reply. Permission: Automation
   (Jarvis → Mail). Nothing new to build.
2. **Gmail in Chrome/Arc:** turn on Gmail's desktop notifications (Gmail → Settings → Desktop
   notifications) and source #3 shows each new mail.
3. **Gmail API, direct (no Apple Mail):**
   - Google Cloud console: create a project, enable the Gmail API, create an OAuth client of
     type *Desktop app*. Scope: `https://www.googleapis.com/auth/gmail.metadata` (headers only)
     or `gmail.readonly`. While the app is in *Testing*, add the users as test users (up to
     100); publishing for everyone needs Google's verification (restricted scope).
   - Sign-in: OAuth 2.0 with PKCE and a loopback redirect (`http://127.0.0.1:<port>`), opened in
     the browser with `NSWorkspace.open`; a tiny local listener receives the code. Store the
     refresh token in the Keychain (`KeychainStore`), never on disk.
   - New mail: on first run, save `historyId` from `GET users/me/profile`; then every 60 s,
     `GET users/me/history?startHistoryId=…&historyTypes=messageAdded&labelId=INBOX`; for each
     new id, `GET users/me/messages/{id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject`.
     Unread count: `GET users/me/labels/INBOX` → `messagesUnread`. (Push through Pub/Sub needs a
     server — not worth it for a desktop app.)
   - Model it like the other pollers (`VercelPoller.swift`: timer, Keychain token, publish to
     `AppState`, `.hookReveal` on new items).

## 6. Xcode ⬜

- Every build writes `~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/Logs/Build/LogStoreManifest.plist`.
  Checked on this Mac: each entry in `logs` has `title` ("Building project NotchBuddy with
  scheme NotchBuddy…"), `schemeIdentifier-schemeName`, `timeStartedRecording`,
  `timeStoppedRecording` (Core Data timestamps) and `primaryObservable` with
  `highLevelStatus` (`S` succeeded, `W` warnings, `E` errors), `totalNumberOfErrors`,
  `totalNumberOfWarnings`, `totalNumberOfTestFailures`.
- Read: watch the DerivedData folder (FSEvents) for changed `LogStoreManifest.plist`; take the
  entry with the latest `timeStoppedRecording`. Headline: "NotchBuddy: build failed · 3
  errors" / "Build succeeded · 2 warnings" / "Tests: 1 failure". Level `.error` on `E`.
- "Building now": Xcode is building while a new entry hasn't been written yet — optionally read
  Xcode's window toolbar status through Accessibility ("Building…", "Build Succeeded").
- Also worth it: Simulator running (`com.apple.iphonesimulator`), archive/upload status (same
  manifest, `domainType` other than BuildLog).

## 7. Android Studio ⬜

- Log: `~/Library/Logs/Google/AndroidStudio<version>/idea.log` — use the newest version folder
  (on this Mac: `AndroidStudio2026.1.3`). Tail it from the last offset (file source on the file,
  handle rotation to `idea.1.log`).
- Lines seen on this Mac:
  - `… GradleSyncStateHolder - Gradle sync finished in 22 s 544 ms`
  - `… GradleSyncStateHolder - Gradle sync failed in 51 s 802 ms. Incompatible Gradle JVM version`
- Also look for build results (`BUILD SUCCESSFUL` / `BUILD FAILED` and "Gradle build finished")
  — confirm the exact text by running a build and reading the log; put the regexes in
  `AppStatusLogic` with tests built from real lines.
- Headline: "Sync failed: Incompatible Gradle JVM version" (`.error`), "Build finished in 1 m
  2 s" (`.done`), "Syncing…" between a start and an end line.
- Emulator: running if `qemu-system-*` is running; device connected through `adb devices` (only
  if adb is installed — don't bundle it).

## 8. DaVinci Resolve ⬜

- Log: `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/logs/davinci_resolve.log`
  (rotates to `.1`, `.2`…). Lines look like
  `0x… | UI.ActionManager | WARN | 2026-11-14 19:42:43,712 | …`. Render start/finish lines are
  not yet confirmed: run a render, then grep the log for the job and write the parser from those
  lines (with tests).
- Better, if you have Resolve Studio: the scripting API (`DaVinciResolveScript`, Python) —
  `project.GetRenderJobList()`, `project.GetRenderJobStatus(jobId)` (`JobStatus`,
  `CompletionPercentage`, `EstimatedTimeRemainingInMs`). External scripting must be enabled
  (Preferences → System → General → External scripting using: Local). Run a small bundled
  Python script from Jarvis every few seconds while Resolve is rendering; show "Rendering 42 %
  · 3 min left", then "Render finished".
- Notifications Resolve shows go through #3 as well.

## 9. Chrome and Arc 🟡

- Dock badge ✅ (Chrome shows downloads count; Arc shows nothing by default).
- Web notifications (Gmail, WhatsApp Web, Slack, Calendar) → source #3. That's the main value.
- Downloads finished: watch `~/Downloads` for new files whose name doesn't end with
  `.crdownload` (Chrome) / `.download`.
- More (open tabs, a site's unread count): a small browser extension + native messaging host
  (`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/` and the Arc equivalent)
  that sends tab titles like "(3) Inbox" to Jarvis over the existing local socket. Bigger job;
  only if #3 isn't enough.

---

## Testing checklist for each new source

- Pure parsing in `AppStatusModel.swift` (or a sibling file) with tests in `tests/` and a
  `scripts/test-<name>.sh`, built from real samples (copy real log lines / plist entries).
- Build: `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug build`.
- Run it, turn on the Apps pill (Settings → Active pills — max 4 pills), trigger the event
  (a failing build, a message to yourself), and check: the row updates, the pill line changes,
  the island pops up once, nothing pops up again after a restart.
- Off means off: with the pill disabled, no timers, no file watchers.
