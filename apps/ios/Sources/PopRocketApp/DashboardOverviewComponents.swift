import Foundation
import PopRocketKit
import SwiftUI

struct HoldToRunControl<Label: View>: View {
    let isEnabled: Bool
    let tint: Color
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let action: () -> Void
    @ViewBuilder let label: (Bool) -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHolding = false

    var body: some View {
        label(isHolding && isEnabled)
            .contentShape(RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .scaleEffect(isHolding && isEnabled && !reduceMotion ? 0.982 : 1)
            .brightness(isHolding && isEnabled ? -0.020 : 0)
            .overlay(alignment: .bottomLeading) {
                if isHolding && isEnabled {
                    Capsule()
                        .fill(tint.opacity(0.70))
                        .frame(height: 3)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(reduceMotion ? nil : AppDesign.Motion.press, value: isHolding)
            .onLongPressGesture(minimumDuration: 0.58, maximumDistance: 24) {
                guard isEnabled else {
                    return
                }
                isHolding = false
                AppFeedback.selection()
                action()
            } onPressingChanged: { pressing in
                guard isEnabled else {
                    return
                }
                if pressing && !isHolding {
                    AppFeedback.selection()
                }
                isHolding = pressing
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAction {
                guard isEnabled else {
                    return
                }
                action()
            }
    }
}

struct DashboardHeaderMetric: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    var isStale: Bool
}

struct DashboardActionModeItem: Identifiable {
    var id: DashboardActionMode { mode }
    let mode: DashboardActionMode
    let value: String
    let detail: String
    let tint: Color
    let kind: AppStatusKind
}

struct DashboardActionModeSelector: View {
    let items: [DashboardActionModeItem]
    let selectedMode: DashboardActionMode
    let select: (DashboardActionMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button {
                    select(item.mode)
                } label: {
                    DashboardActionModeTile(
                        item: item,
                        selected: item.mode == selectedMode
                    )
                }
                .buttonStyle(AppPressButtonStyle(tint: item.tint, isEnabled: true))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(item.mode.title), \(item.value), \(item.detail)")
                .accessibilityAddTraits(item.mode == selectedMode ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppDesign.panelFill, in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .background(AppDesign.Palette.action.opacity(0.035), in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous)
                .stroke(AppDesign.Palette.action.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action mode")
    }
}

struct DashboardActionModeTile: View {
    let item: DashboardActionModeItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.mode.systemImage)
                .font(.caption.weight(.bold))
            Text(item.mode.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(selected ? item.tint : AppDesign.Palette.stale)
        .background(selected ? item.tint.opacity(0.20) : Color.clear, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(selected ? item.tint.opacity(0.36) : Color.clear, lineWidth: 1)
        }
    }
}

struct DashboardOperationsHeader: View {
    let credential: PairingCredential?
    let bridgeHealthy: Bool
    let bridgeReachable: Bool
    let statusText: String
    let bridgeHealth: BridgeHealth?
    let metrics: [DashboardHeaderMetric]
    let lastConfirmedText: String?
    let showsFocusRow: Bool
    let focusTitle: String
    let focusDetail: String
    let focusSystemImage: String
    let focusKind: AppStatusKind
    let primaryTitle: String
    let primarySystemImage: String
    let primaryKind: AppStatusKind
    let primaryAction: () -> Void
    let isRefreshing: Bool
    let refresh: () -> Void
    let pairBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                AppIconBubble(systemImage: bridgeIconName, tint: statusTint, size: 34)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(contextLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .lineLimit(1)
                        if credential != nil {
                            AppStateLine(
                                title: statusPillText,
                                detail: bridgeHealth.map { "up \(AppFormat.shortDuration(seconds: $0.uptimeSeconds))" },
                                kind: statusKind
                            )
                        }
                    }
                    Text(bridgeTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    if let trustLine {
                        Text(trustLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if credential != nil {
                    AppIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Refresh Dashboard",
                        tint: AppDesign.Palette.action,
                        isRunning: isRefreshing,
                        runningReason: "Refreshing bridge status, health checks, actions, and activity.",
                        action: refresh
                    )
                }
            }

            if credential != nil, !metrics.isEmpty {
                CompactMetricPillRow(metrics: metrics)
            }

            if credential == nil {
                SetupBridgePrompt(pairBridge: pairBridge)
            } else if showsFocusRow {
                DashboardHeaderFocusRow(
                    title: focusTitle,
                    detail: focusDetail,
                    systemImage: focusSystemImage,
                    kind: focusKind,
                    showsPrimaryAction: focusKind != .success,
                    primaryTitle: primaryTitle,
                    primarySystemImage: primarySystemImage,
                    primaryKind: primaryKind,
                    primaryAction: primaryAction
                )
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: DashboardDesign.sectionCornerRadius, style: .continuous)
                .fill(DashboardDesign.sectionFill)
            RoundedRectangle(cornerRadius: DashboardDesign.sectionCornerRadius, style: .continuous)
                .fill(statusTint.opacity(credential == nil ? 0.080 : 0.050))
        }
        .overlay(
            RoundedRectangle(cornerRadius: DashboardDesign.sectionCornerRadius, style: .continuous)
                .stroke(statusTint.opacity(credential == nil ? 0.24 : 0.18), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(statusTint)
                .frame(width: 5)
                .opacity(credential == nil ? 0.78 : 0.88)
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardDesign.sectionCornerRadius, style: .continuous))
        .shadow(color: statusTint.opacity(0.065), radius: 14, x: 0, y: 6)
    }

    private var bridgeTitle: String {
        credential?.bridgeName ?? "Add a Bridge"
    }

    private var contextLabel: String {
        guard credential != nil else {
            return "Bridge"
        }
        return bridgeReachable ? "Live Bridge" : "Cached Bridge"
    }

    private var trustLine: String? {
        guard let credential else {
            return "Connect one trusted LAN bridge to monitor health, run actions, and wake devices."
        }
        if bridgeReachable {
            return nil
        }
        if let lastConfirmedText {
            return "Cached from \(credential.bridgeName). Last confirmed \(lastConfirmedText). Actions paused."
        }
        return "Cached from \(credential.bridgeName). No confirmed cache yet. Actions paused."
    }

    private var statusPillText: String {
        guard credential != nil else {
            return "Not Added"
        }
        return statusText
    }

    private var statusKind: AppStatusKind {
        guard credential != nil else {
            return .stale
        }
        if bridgeHealthy {
            return .success
        }
        return bridgeReachable ? .warning : .stale
    }

    private var bridgeIconName: String {
        if bridgeHealthy {
            return "checkmark.circle.fill"
        }
        if bridgeReachable {
            return "exclamationmark.triangle.fill"
        }
        return credential == nil ? "link.badge.plus" : "clock.badge.exclamationmark"
    }

    private var statusTint: Color {
        guard credential != nil else {
            return AppDesign.Palette.bridge
        }
        if bridgeHealthy {
            return AppDesign.Palette.success
        }
        return bridgeReachable ? AppDesign.Palette.warning : AppDesign.Palette.cached
    }

}

struct DashboardHeaderFocusRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let kind: AppStatusKind
    let showsPrimaryAction: Bool
    let primaryTitle: String
    let primarySystemImage: String
    let primaryKind: AppStatusKind
    let primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kind.color)
                    .frame(width: 30, height: 30)
                    .background(kind.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(title: badgeTitle, kind: kind, systemImage: kind.symbolName)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if showsPrimaryAction {
                AppActionButton(
                    title: primaryTitle,
                    systemImage: primarySystemImage,
                    kind: primaryKind,
                    action: primaryAction
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        switch kind {
        case .success:
            return "CONFIRMED"
        case .warning:
            return "CHECK"
        case .stale:
            return "VERIFY"
        case .action:
            return "OPEN"
        case .destructive:
            return "SECURITY"
        }
    }
}

struct CompactMetricPillRow: View {
    let metrics: [DashboardHeaderMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                ForEach(metrics) { metric in
                    DashboardMetricTile(metric: metric, compact: true)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 7) {
                ForEach(metrics) { metric in
                    DashboardMetricTile(metric: metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(metrics) { metric in
                    DashboardMetricTile(metric: metric)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 112), spacing: 7),
            GridItem(.flexible(minimum: 112), spacing: 7)
        ]
    }
}

struct DashboardMetricTile: View {
    let metric: DashboardHeaderMetric
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(resolvedColor)
                    .frame(width: 18, height: 18)
                    .background(resolvedColor.opacity(0.15), in: Circle())
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                Spacer(minLength: 0)
                Circle()
                    .fill(resolvedColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }

            Text(metric.value)
                .font(AppDesign.Typography.dashboardMetricValue)
                .foregroundStyle(resolvedColor)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            if !compact {
                Text(metric.detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 7 : 9)
        .frame(maxWidth: .infinity, minHeight: compact ? 58 : 78, alignment: .topLeading)
        .background(resolvedColor.opacity(metric.isStale ? 0.060 : 0.095), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(resolvedColor.opacity(metric.isStale ? 0.16 : 0.26), lineWidth: 1)
        }
        .accessibilityLabel("\(metric.title), \(metric.value), \(metric.detail)")
    }

    private var resolvedColor: Color {
        metric.isStale ? AppDesign.Palette.stale : metric.tint
    }
}

struct SetupBridgePrompt: View {
    let pairBridge: () -> Void

    var body: some View {
        AppActionButton(
            title: "Add Bridge",
            systemImage: "link.badge.plus",
            kind: .action,
            action: pairBridge
        )
        .accessibilityLabel("Add a trusted local bridge.")
    }
}

struct BridgeRequiredPanel: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let pairBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AppIconBubble(systemImage: systemImage, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            AppActionButton(
                title: "Add Bridge",
                systemImage: "link.badge.plus",
                kind: .action,
                action: pairBridge
            )
            .accessibilityLabel("Add a trusted local bridge.")
        }
        .padding(14)
        .appSemanticPanel(tint: tint, prominence: .standard)
    }
}

struct ActionAuthorityStrip: View {
    let mode: DashboardActionMode
    let bridgeName: String
    let bridgeReachable: Bool
    let bridgeHealthy: Bool
    let lastConfirmedText: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppIconBubble(systemImage: mode.systemImage, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    AppStatusBadge(title: badgeTitle, kind: kind, systemImage: kind.symbolName)
                }
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .appSemanticPanel(
            tint: tint,
            isActive: bridgeReachable,
            prominence: .quiet,
            showsRail: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: String {
        switch mode {
        case .wake:
            return "Wake Through \(bridgeName)"
        case .run:
            return "Run Through \(bridgeName)"
        }
    }

    private var detail: String? {
        if bridgeHealthy {
            return nil
        }
        if bridgeReachable {
            switch mode {
            case .wake:
                return "Wake-on-LAN requests use this bridge."
            case .run:
                return "Command tiles and one-off commands execute on this bridge."
            }
        }
        if let lastConfirmedText {
            return "Cached from \(bridgeName). Last confirmed \(lastConfirmedText). Reconnect before running actions."
        }
        return "Cached from \(bridgeName). No confirmed cache yet. Reconnect before running actions."
    }

    private var accessibilityLabel: String {
        if let detail {
            return "\(title), \(badgeTitle), \(detail)"
        }
        return "\(title), \(badgeTitle)"
    }

    private var badgeTitle: String {
        if bridgeHealthy {
            return "Live"
        }
        if bridgeReachable {
            return "Check"
        }
        return "Cached"
    }

    private var kind: AppStatusKind {
        if bridgeHealthy {
            return .success
        }
        if bridgeReachable {
            return .warning
        }
        return .stale
    }

    private var tint: Color {
        if !bridgeReachable {
            return AppDesign.Palette.stale
        }
        switch mode {
        case .wake:
            return AppDesign.Palette.wake
        case .run:
            return AppDesign.Palette.command
        }
    }
}

struct DashboardTabHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    let hasBridge: Bool
    let bridgeTitle: String
    let bridgeStatusTitle: String
    let bridgeStatusDetail: String?
    let bridgeStatusKind: AppStatusKind
    let isRefreshing: Bool
    let refresh: () -> Void
    let pairBridge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: Circle())

                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 0)

                if hasBridge {
                    AppIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Refresh",
                        tint: AppDesign.Palette.action,
                        isRunning: isRefreshing,
                        runningReason: "Refreshing this screen from the active bridge.",
                        action: refresh
                    )
                }
            }

            if hasBridge, let contextLine {
                HStack(alignment: .center, spacing: 8) {
                    AppStatusBadge(
                        title: badgeTitle,
                        kind: bridgeStatusKind,
                        systemImage: bridgeStatusKind.symbolName
                    )
                    Text(contextLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        guard hasBridge else {
            return "LOCKED"
        }
        switch bridgeStatusKind {
        case .success:
            return "LIVE"
        case .warning:
            return "CHECK"
        case .stale:
            return "CACHED"
        case .action:
            return "OPEN"
        case .destructive:
            return "SECURITY"
        }
    }

    private var contextLine: String? {
        guard hasBridge else {
            return nil
        }
        guard bridgeStatusKind != .success else {
            return nil
        }
        if let bridgeStatusDetail, !bridgeStatusDetail.isEmpty {
            return "\(bridgeTitle) · \(bridgeStatusDetail)"
        }
        return "\(bridgeTitle) · \(bridgeStatusTitle)"
    }
}

struct DashboardNavigationButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
            }
            .padding(12)
            .appSemanticPanel(tint: tint, prominence: .quiet, showsRail: false)
        }
        .buttonStyle(AppPressButtonStyle(tint: tint))
        .accessibilityLabel("\(title), \(detail)")
    }
}

struct OverviewActionTileContent: View {
    let title: String
    let actionLabel: String
    let iconName: String
    let tint: Color
    let isRunning: Bool
    let bridgeName: String
    let bridgeReachable: Bool
    let widgetPinned: Bool
    let configManaged: Bool
    let statusTitle: String
    let statusDetail: String?
    let statusKind: AppStatusKind
    let isHolding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AppIconBubble(systemImage: iconName, tint: tint, size: 28)
                Spacer(minLength: 0)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                Text(actionLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ActionContextChipRow(
                    bridgeName: bridgeName,
                    bridgeReachable: bridgeReachable,
                    widgetPinned: widgetPinned,
                    configManaged: configManaged,
                    showBridgeChip: !bridgeReachable
                )
            }

            Spacer(minLength: 0)

            AppStateLine(
                title: isHolding ? "Holding" : statusTitle,
                detail: isHolding ? "keep holding" : statusDetail,
                kind: statusKind
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
    }
}

struct OverviewWakeActionTile: View {
    let target: WOLTarget
    let state: WOLActionState?
    let isEnabled: Bool
    let disabledReason: String?
    let bridgeName: String
    let bridgeReachable: Bool
    let lastUpdatedAt: Date?
    let widgetPinned: Bool
    let action: () -> Void

    var body: some View {
        HoldToRunControl(
            isEnabled: isEnabled && !isRunning,
            tint: tileTint,
            accessibilityLabel: "Wake \(target.name)",
            accessibilityValue: accessibilityState,
            accessibilityHint: accessibilityHint,
            action: action
        ) { isHolding in
            OverviewActionTileContent(
                title: target.name,
                actionLabel: "Wake",
                iconName: iconName,
                tint: tileTint,
                isRunning: isRunning,
                bridgeName: bridgeName,
                bridgeReachable: bridgeReachable,
                widgetPinned: widgetPinned,
                configManaged: target.source == "config",
                statusTitle: statusTitle,
                statusDetail: statusDetail,
                statusKind: statusKind,
                isHolding: isHolding
            )
        }
        .appActionSurface(tint: tileTint, isEnabled: isEnabled || state != nil)
        .opacity(isEnabled || state != nil ? 1 : DashboardDesign.disabledOpacity)
        .animation(AppDesign.Motion.stateChange, value: statusTitle)
        .animation(AppDesign.Motion.stateChange, value: isRunning)
    }

    private var isRunning: Bool {
        state?.running == true
    }

    private var statusTitle: String {
        if isRunning {
            return "Waking"
        }
        if state?.succeeded == true {
            return "Sent"
        }
        if state != nil {
            return "Failed"
        }
        if isEnabled && bridgeReachable {
            return "Can Wake"
        }
        return "Cached"
    }

    private var statusDetail: String? {
        if let state {
            var parts: [String] = []
            if let updatedAt = state.updatedAt {
                parts.append(AppFormat.relativeShort(updatedAt))
            }
            parts.append(state.bridgeName?.nilIfBlank ?? bridgeName)
            return parts.joined(separator: " · ")
        }
        if !isEnabled {
            return disabledReason
        }
        if !bridgeReachable, let lastUpdatedAt {
            return "last confirmed \(AppFormat.relativeShort(lastUpdatedAt))"
        }
        return "Hold to wake"
    }

    private var statusKind: AppStatusKind {
        if isRunning {
            return .action
        }
        if state?.succeeded == true {
            return .success
        }
        if state != nil {
            return .warning
        }
        if isEnabled && bridgeReachable {
            return .action
        }
        return .stale
    }

    private var iconName: String {
        if isRunning {
            return "hourglass"
        }
        if state?.succeeded == true {
            return "checkmark.circle.fill"
        }
        if state != nil {
            return "exclamationmark.triangle.fill"
        }
        return "power"
    }

    private var tileTint: Color {
        if isRunning {
            return AppDesign.Palette.wake
        }
        if state?.succeeded == true {
            return AppDesign.Palette.success
        }
        if state != nil {
            return AppDesign.Palette.warning
        }
        if isEnabled && bridgeReachable {
            return AppDesign.Palette.wake
        }
        return AppDesign.Palette.stale
    }

    private var accessibilityState: String {
        [statusTitle, statusDetail].compactMap(\.self).joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if isRunning {
            return "Wake request is running through \(bridgeName)."
        }
        if !isEnabled {
            return disabledReason ?? "Wake is unavailable."
        }
        if bridgeReachable {
            return "Hold to send Wake-on-LAN through \(bridgeName)."
        }
        return "Cached from \(bridgeName). Reconnect the bridge before waking this device."
    }

}

struct OverviewCommandActionTile: View {
    let shortcut: CommandShortcut
    let isRunning: Bool
    let commandRunning: Bool
    let bridgeName: String
    let bridgeReachable: Bool
    let commandEnabled: Bool
    let disabledReason: String?
    let widgetPinned: Bool
    let action: () -> Void

    var body: some View {
        HoldToRunControl(
            isEnabled: commandEnabled && !commandRunning,
            tint: tileTint,
            accessibilityLabel: "Run \(shortcut.name)",
            accessibilityValue: accessibilityState,
            accessibilityHint: accessibilityHint,
            action: action
        ) { isHolding in
            OverviewActionTileContent(
                title: shortcut.name,
                actionLabel: "Command",
                iconName: iconName,
                tint: tileTint,
                isRunning: isRunning,
                bridgeName: bridgeName,
                bridgeReachable: bridgeReachable,
                widgetPinned: widgetPinned,
                configManaged: false,
                statusTitle: statusTitle,
                statusDetail: statusDetail,
                statusKind: statusKind,
                isHolding: isHolding
            )
        }
        .appActionSurface(tint: tileTint, isEnabled: commandEnabled || isRunning)
        .opacity((commandRunning && !isRunning) || !commandEnabled ? DashboardDesign.disabledOpacity : 1)
        .animation(AppDesign.Motion.stateChange, value: statusTitle)
        .animation(AppDesign.Motion.stateChange, value: isRunning)
    }

    private var statusTitle: String {
        if isRunning {
            return "Running"
        }
        if !commandEnabled {
            return "Unavailable"
        }
        if commandRunning {
            return "Busy"
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return Self.displayStatus(status)
        }
        return "Can Run"
    }

    private var statusDetail: String? {
        if isRunning {
            return nil
        }
        if !commandEnabled {
            return disabledReason
        }
        if commandRunning {
            return "Another command is running"
        }
        if let lastRunAt = shortcut.lastRunAt {
            let relativeRun = AppFormat.relativeShort(lastRunAt)
            return bridgeReachable ? relativeRun : "\(relativeRun) · \(bridgeName)"
        }
        return "Hold to run"
    }

    private var statusKind: AppStatusKind {
        if isRunning {
            return .action
        }
        if !commandEnabled || commandRunning {
            return .stale
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return AppStatusKind(status: status)
        }
        return .action
    }

    private var iconName: String {
        if isRunning {
            return "hourglass"
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return AppStatusKind(status: status).symbolName
        }
        return "terminal"
    }

    private var tileTint: Color {
        if isRunning {
            return AppDesign.Palette.command
        }
        if !commandEnabled || commandRunning {
            return AppDesign.Palette.stale
        }
        if let status = shortcut.lastStatus?.nilIfBlank {
            return AppStatusKind(status: status).color
        }
        return AppDesign.Palette.command
    }

    private var accessibilityState: String {
        [statusTitle, statusDetail].compactMap(\.self).joined(separator: ", ")
    }

    private var accessibilityHint: String {
        if isRunning {
            return "Command is running through \(bridgeName)."
        }
        if !commandEnabled {
            return disabledReason ?? "Command runner is unavailable."
        }
        if commandRunning {
            return "Another command is already running."
        }
        if bridgeReachable {
            return "Hold to run this saved command through \(bridgeName)."
        }
        return "Cached from \(bridgeName). Reconnect the bridge before running this command."
    }

    private static func displayStatus(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed":
            return "Ran"
        case "failed", "request failed":
            return "Failed"
        case "accepted":
            return "Accepted"
        default:
            return AppDesign.statusLabel(status)
        }
    }

}

struct OverviewSetupActionTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let kind: AppStatusKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    AppIconBubble(systemImage: systemImage, tint: tint, size: 28)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint)
                        .opacity(0.76)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                AppStateLine(title: "Configure", detail: nil, kind: kind)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        }
        .buttonStyle(AppPressButtonStyle(tint: tint, isEnabled: true))
        .appActionSurface(tint: tint, isEnabled: true)
        .accessibilityLabel(title)
    }
}

struct DashboardSubsectionHeader: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}

struct DashboardSectionBand<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeTitle: String? = nil
    var badgeKind: AppStatusKind? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(resolvedTint)
                    .frame(width: 30, height: 30)
                    .background(resolvedTint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppDesign.Typography.dashboardSectionTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let badgeTitle {
                    AppStatusBadge(
                        title: badgeTitle,
                        kind: badgeKind ?? .stale,
                        systemImage: badgeKind?.symbolName
                    )
                }
            }
            .accessibilityElement(children: .combine)

            content
        }
        .padding(.horizontal, DashboardDesign.pagePadding)
        .padding(.vertical, 14)
        .background {
            Rectangle()
                .fill(DashboardDesign.sectionFill)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            resolvedTint.opacity(0.070),
                            resolvedTint.opacity(0.026)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(resolvedTint)
                .frame(width: 4)
                .opacity(0.78)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(resolvedTint.opacity(0.16))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DashboardDesign.sectionStroke)
                .frame(height: 1)
        }
        .padding(.horizontal, -DashboardDesign.pagePadding)
        .accessibilityElement(children: .contain)
    }

    private var resolvedTint: Color {
        badgeKind?.color ?? tint
    }
}
