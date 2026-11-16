#if !APPSTORE
import SwiftUI

// MARK: - Apps card

/// The open Apps pill: one row per installed app, Claude first, each with its icon, what it's
/// doing and its Dock badge. A click brings the app forward.
struct AppStatusCardView: View {
    @ObservedObject private var hub = AppStatusHub.shared

    private var rows: [AppStatus] { hub.statuses.filter(\.installed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: PillCatalog.definition(for: AppStatusHub.pillId)?.color ?? "#64748B"))
                    .frame(width: 7, height: 7)
                Text(String(localized: "apps.title", defaultValue: "Apps"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 2)
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            if !hub.accessibilityTrusted {
                accessibilityRow
                    .padding(.top, 4)
                    .padding(.leading, 108)
                    .padding(.trailing, 12)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows) { status in
                        AppStatusRow(status: status) { hub.open(status.app) }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { hub.refresh() }
    }

    private var accessibilityRow: some View {
        HStack(spacing: 6) {
            Text(String(localized: "apps.accessibility-needed",
                        defaultValue: "Allow Accessibility to see badges and Claude's replies."))
                .font(.system(size: 10.5))
                .foregroundColor(Color(hex: "#F5B14C"))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button(String(localized: "apps.allow", defaultValue: "Allow")) { hub.askForAccessibility() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#041018"))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "#F5B14C")))
        }
    }
}

struct AppStatusRow: View {
    let status: AppStatus
    let onOpen: () -> Void
    @State private var hovered = false

    private var levelColor: Color {
        switch status.level {
        case .error:     return Color(hex: "#F4505E")
        case .attention: return Color(hex: "#F5B14C")
        case .working:   return Color(hex: "#3B9EFF")
        case .done:      return Color(hex: "#34D399")
        case .idle:      return Color.white.opacity(0.35)
        case .off:       return Color.white.opacity(0.15)
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                if let icon = AppStatusHub.shared.icon(for: status.app) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .opacity(status.running ? 1 : 0.45)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(verbatim: status.app.name)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color(hex: status.running ? "#F5F6F8" : "#8E939C"))
                        Circle().fill(levelColor).frame(width: 5, height: 5)
                        Text(status.headline)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .lineLimit(1)
                    }
                    ForEach(status.lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let badge = status.badge {
                    Text(verbatim: badge)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Color(hex: "#F4505E")))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hovered ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Settings

/// Settings → Integrations → Apps.
struct AppStatusSettingsSection: View {
    @ObservedObject private var hub = AppStatusHub.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: PillCatalog.definition(for: AppStatusHub.pillId)?.color ?? "#64748B"))
                    .frame(width: 8, height: 8)
                Text(String(localized: "apps.title", defaultValue: "Apps")).font(.system(size: 12, weight: .semibold))
            }
            Text(String(localized: "apps.settings-footer",
                        defaultValue: "Claude, Xcode, Android Studio, Chrome, Arc and DaVinci Resolve in one pill, Claude first: which are open, their Dock badges, and for Claude your Claude Code sessions, the Claude app's replies and your plan. Turn the pill on in Active pills."))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !hub.accessibilityTrusted {
                HStack(spacing: 8) {
                    Text(String(localized: "apps.accessibility-needed",
                                defaultValue: "Allow Accessibility to see badges and Claude's replies."))
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Button(String(localized: "apps.allow", defaultValue: "Allow")) { hub.askForAccessibility() }
                }
            }
        }
    }
}
#endif
