import Foundation
import PopRocketKit
import SwiftUI

struct CardRow: View {
    let card: CardSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: card.stale ? AppStatusKind.stale.symbolName : "rectangle.stack.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cardStatusKind.color)
                .frame(width: 30, height: 30)
                .background(cardStatusKind.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    AppStatusBadge(status: card.stale ? "stale" : card.status)
                }
                Text(card.error?.nilIfBlank ?? card.value?.displayText ?? card.kind)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(card.stale ? "Last confirmed" : "Updated") \(card.updatedAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .appSemanticPanel(tint: cardStatusKind.color, prominence: .quiet)
    }

    private var cardStatusKind: AppStatusKind {
        card.stale ? .stale : AppStatusKind(status: card.status)
    }
}

struct SectionNoticeRow: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: .quiet)
    }
}

struct SectionStatusRow: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var progress = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if progress {
                ProgressView()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12), in: Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .appSemanticPanel(tint: tint, prominence: progress ? .standard : .quiet)
    }
}

struct ActionMetaChip: View {
    let title: String
    let systemImage: String
    var kind: AppStatusKind = .stale
    var maxWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
            .font(AppDesign.Typography.metadata)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .foregroundStyle(kind.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(maxWidth: maxWidth, alignment: .leading)
        .background(kind.color.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct ActionMetaIconChip: View {
    let title: String
    let systemImage: String
    var kind: AppStatusKind

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.color)
            .frame(width: 24, height: 22)
            .background(kind.color.opacity(0.10), in: Capsule())
            .accessibilityLabel(title)
    }
}

struct ActionContextChipRow: View {
    let bridgeName: String
    let bridgeReachable: Bool
    let widgetPinned: Bool
    let configManaged: Bool
    var showBridgeChip = false

    var body: some View {
        if showsAnyChip {
            ViewThatFits(in: .horizontal) {
                fullChipRow
                compactChipRow
                compactFallbackChipRow
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        }
    }

    private var fullChipRow: some View {
        HStack(spacing: 6) {
            if showBridgeChip {
                bridgeChip(maxWidth: 118)
            }
            if widgetPinned {
                ActionMetaChip(
                    title: "Trusted",
                    systemImage: "checkmark.seal.fill",
                    kind: .success
                )
            }
            if configManaged {
                ActionMetaChip(
                    title: "Config",
                    systemImage: "lock.fill",
                    kind: .stale
                )
            }
        }
    }

    private var compactChipRow: some View {
        HStack(spacing: 5) {
            if showBridgeChip {
                bridgeChip(maxWidth: 112)
            }
            if widgetPinned {
                ActionMetaIconChip(
                    title: "Trusted for widgets",
                    systemImage: "checkmark.seal.fill",
                    kind: .success
                )
            }
            if configManaged {
                ActionMetaIconChip(
                    title: "Config managed",
                    systemImage: "lock.fill",
                    kind: .stale
                )
            }
        }
    }

    private var compactFallbackChipRow: some View {
        HStack(spacing: 5) {
            if showBridgeChip {
                bridgeChip(maxWidth: 132)
            }
            if widgetPinned {
                ActionMetaIconChip(
                    title: "Trusted for widgets",
                    systemImage: "checkmark.seal.fill",
                    kind: .success
                )
            } else if configManaged {
                ActionMetaIconChip(
                    title: "Config managed",
                    systemImage: "lock.fill",
                    kind: .stale
                )
            }
        }
    }

    private func bridgeChip(maxWidth: CGFloat) -> some View {
        ActionMetaChip(
            title: bridgeName.nilIfBlank ?? "Bridge",
            systemImage: "antenna.radiowaves.left.and.right",
            kind: bridgeReachable ? .action : .stale,
            maxWidth: maxWidth
        )
    }

    private var showsAnyChip: Bool {
        showBridgeChip || widgetPinned || configManaged
    }
}

struct ActionTileFooter: View {
    let title: String
    let systemImage: String
    let kind: AppStatusKind
    var tint: Color? = nil
    var isRunning = false
    var isEnabled = true
    var isHolding = false

    var body: some View {
        HStack(spacing: 7) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isEnabled ? systemImage : "lock.fill")
                    .font(.caption.weight(.bold))
            }
            Text(title)
                .font(AppDesign.Typography.controlLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
            if isEnabled && !isRunning {
                Image(systemName: isHolding ? "hand.tap.fill" : "hand.tap")
                    .font(.caption2.weight(.bold))
                    .opacity(isHolding ? 1 : 0.76)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 10)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var activeColor: Color {
        if isEnabled || isRunning {
            return tint ?? kind.color
        }
        return AppDesign.Palette.stale
    }

    private var foregroundColor: Color {
        activeColor
    }

    private var backgroundColor: Color {
        activeColor.opacity(isHolding ? 0.24 : 0.16)
    }

    private var borderColor: Color {
        activeColor.opacity(isHolding ? 0.40 : 0.28)
    }
}

struct WidgetTrustButtonLabel: View {
    let isTrusted: Bool

    var body: some View {
        Label(labelTitle, systemImage: isTrusted ? "checkmark.seal.fill" : "checkmark.seal")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: 68, height: AppDesign.Size.iconButton)
            .foregroundStyle(tint)
            .background(tint.opacity(isTrusted ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .stroke(tint.opacity(isTrusted ? 0.24 : 0.16), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    private var labelTitle: String {
        isTrusted ? "Trusted" : "Trust"
    }

    private var tint: Color {
        isTrusted ? AppDesign.Palette.success : AppDesign.Palette.stale
    }
}

struct FormValidationRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(AppDesign.Palette.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

struct FormErrorRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(AppDesign.Palette.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

struct ActivityTimelineRow: View {
    let record: AuditRecord
    let bridgeName: String
    let isLive: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            timelineRail
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    AppStatusBadge(title: AppDesign.statusLabel(record.status).uppercased(), kind: statusKind, systemImage: iconName)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Label(actionKind, systemImage: actionIconName)
                        Text("·")
                        Text(record.createdAt, style: .relative)
                        Text("·")
                        Text(bridgeContext)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Label(actionKind, systemImage: actionIconName)
                            Text("·")
                            Text(record.createdAt, style: .relative)
                        }
                        Text(bridgeContext)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let durationText {
                    AppStateLine(
                        title: "Duration",
                        detail: durationText,
                        kind: statusKind == .warning ? .warning : .stale
                    )
                }

                if let message = record.resultMessage, !message.isEmpty {
                    resultBlock(message)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var title: String {
        if let target = record.actionID.stripPrefix("wol:") {
            return "Wake \(target)"
        }
        if record.actionID == "command:run" {
            return "Command"
        }
        return record.actionID
    }

    private var actionKind: String {
        if record.actionID.hasPrefix("wol:") {
            return "Wake"
        }
        if record.actionID.hasPrefix("command:") {
            return "Command"
        }
        return "Action"
    }

    private var actionIconName: String {
        if record.actionID.hasPrefix("wol:") {
            return "power"
        }
        if record.actionID.hasPrefix("command:") {
            return "terminal"
        }
        return "bolt"
    }

    private var bridgeContext: String {
        isLive ? "\(bridgeName) confirmed" : "cached from \(bridgeName)"
    }

    private var iconName: String {
        switch record.status {
        case "completed":
            return "checkmark.circle.fill"
        case "failed", "denied":
            return "exclamationmark.triangle.fill"
        default:
            return "clock"
        }
    }

    private var statusKind: AppStatusKind {
        AppStatusKind(status: record.status)
    }

    private var durationText: String? {
        guard let completedAt = record.completedAt else {
            return nil
        }
        let seconds = completedAt.timeIntervalSince(record.createdAt)
        guard seconds >= 0 else {
            return nil
        }
        if seconds < 1 {
            return "<1s"
        }
        if seconds < 60 {
            return "\(Int(seconds.rounded()))s"
        }
        let minutes = Int(seconds / 60)
        let remainder = Int(seconds.truncatingRemainder(dividingBy: 60).rounded())
        return remainder == 0 ? "\(minutes)m" : "\(minutes)m \(remainder)s"
    }

    private var accessibilitySummary: String {
        var parts = [
            title,
            AppDesign.statusLabel(record.status),
            actionKind,
            isLive ? "\(bridgeName) confirmed" : "cached from \(bridgeName)"
        ]
        if let durationText {
            parts.append("Duration \(durationText)")
        }
        if let message = record.resultMessage?.nilIfBlank {
            parts.append(message)
        }
        return parts.joined(separator: ", ")
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? Color.clear : statusKind.color.opacity(0.24))
                .frame(width: 2, height: 8)
            ZStack {
                Circle()
                    .fill(statusKind.color.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: iconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusKind.color)
            }
            Rectangle()
                .fill(isLast ? Color.clear : statusKind.color.opacity(0.24))
                .frame(width: 2)
                .frame(minHeight: 34, maxHeight: .infinity)
        }
        .frame(width: 30)
        .accessibilityHidden(true)
    }

    private func resultBlock(_ message: String) -> some View {
        Text(message)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(statusKind == .warning ? AppDesign.Palette.warning : AppDesign.Palette.stale)
            .lineLimit(4)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(statusKind.color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
    }
}

struct HealthSummaryRow: View {
    let summary: HealthMonitorSummary
    let isLive: Bool
    let lastUpdatedAt: Date?

    private var upCount: Int {
        summary.upCount
    }

    private var downCount: Int {
        summary.downCount
    }

    private var unknownCount: Int {
        summary.unknownCount
    }

    private var monitorCount: Int {
        summary.sortedMonitors.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        AppStatusBadge(
                            title: isLive ? "LIVE" : "CACHED",
                            kind: isLive ? statusKind : .stale,
                            systemImage: isLive ? "dot.radiowaves.left.and.right" : "clock.badge.exclamationmark"
                        )
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !isLive, let lastUpdatedAt {
                        Text("Last confirmed \(lastUpdatedAt, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            HealthSummaryDistributionBar(
                upCount: upCount,
                downCount: downCount,
                unknownCount: unknownCount
            )

            HealthSummaryCountRow(
                upCount: upCount,
                downCount: downCount,
                unknownCount: unknownCount
            )
        }
        .padding(12)
        .appSemanticPanel(
            tint: statusColor,
            isActive: isLive,
            prominence: downCount > 0 ? .standard : .quiet
        )
    }

    private var title: String {
        if !isLive {
            return "Last Confirmed Health"
        }
        if downCount > 0 {
            return "\(downCount) Down"
        }
        if unknownCount > 0 {
            return "\(unknownCount) Unknown"
        }
        return "All Checks Confirmed"
    }

    private var subtitle: String {
        let counts = "\(upCount) up / \(downCount) down / \(monitorCount) monitored"
        if !isLive {
            return "Bridge offline; showing last confirmed \(counts.lowercased())"
        }
        if unknownCount > 0 {
            return "\(counts), \(unknownCount) unchecked"
        }
        return counts
    }

    private var iconName: String {
        if !isLive {
            return "clock.badge.exclamationmark"
        }
        if downCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if unknownCount > 0 {
            return "questionmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if !isLive || unknownCount > 0 {
            return AppDesign.Palette.stale
        }
        return downCount > 0 ? AppDesign.Palette.warning : AppDesign.Palette.success
    }

    private var statusKind: AppStatusKind {
        if !isLive || unknownCount > 0 {
            return .stale
        }
        return downCount > 0 ? .warning : .success
    }
}

struct HealthSummaryDistributionBar: View {
    let upCount: Int
    let downCount: Int
    let unknownCount: Int

    private var total: Int {
        max(upCount + downCount + unknownCount, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width)
            let upWidth = segmentWidth(upCount, totalWidth: width)
            let downWidth = segmentWidth(downCount, totalWidth: width)
            let unknownWidth = segmentWidth(unknownCount, totalWidth: width)

            HStack(spacing: 0) {
                if upCount > 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.success)
                        .frame(width: upWidth)
                }
                if downCount > 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.warning)
                        .frame(width: downWidth)
                }
                if unknownCount > 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.stale)
                        .frame(width: unknownWidth)
                }
                if upCount + downCount + unknownCount == 0 {
                    Rectangle()
                        .fill(AppDesign.Palette.stale.opacity(0.45))
                }
            }
            .frame(width: width, height: 8, alignment: .leading)
            .background(AppDesign.Palette.stale.opacity(0.14))
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func segmentWidth(_ count: Int, totalWidth: CGFloat) -> CGFloat {
        guard count > 0 else {
            return 0
        }
        return totalWidth * CGFloat(count) / CGFloat(total)
    }
}

struct HealthSummaryCountRow: View {
    let upCount: Int
    let downCount: Int
    let unknownCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                HealthSummaryCountPill(title: "Up", value: upCount, kind: upCount > 0 ? .success : .stale, systemImage: "checkmark.circle.fill")
                HealthSummaryCountPill(title: "Down", value: downCount, kind: downCount > 0 ? .warning : .stale, systemImage: "exclamationmark.triangle.fill")
                HealthSummaryCountPill(title: "Unknown", value: unknownCount, kind: .stale, systemImage: "questionmark.circle.fill")
            }
            VStack(alignment: .leading, spacing: 7) {
                HealthSummaryCountPill(title: "Up", value: upCount, kind: upCount > 0 ? .success : .stale, systemImage: "checkmark.circle.fill")
                HealthSummaryCountPill(title: "Down", value: downCount, kind: downCount > 0 ? .warning : .stale, systemImage: "exclamationmark.triangle.fill")
                HealthSummaryCountPill(title: "Unknown", value: unknownCount, kind: .stale, systemImage: "questionmark.circle.fill")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(upCount) up, \(downCount) down, \(unknownCount) unknown")
    }
}

struct HealthSummaryCountPill: View {
    let title: String
    let value: Int
    let kind: AppStatusKind
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text("\(value) \(title)")
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(kind.color)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(kind.color.opacity(value > 0 ? 0.12 : 0.07), in: Capsule())
        .accessibilityHidden(true)
    }
}

struct HealthMonitorRow: View {
    let monitor: HealthMonitor
    let isLive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 30, height: 30)
                .background(statusColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(monitor.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let sourceLabel {
                        ActionMetaChip(title: sourceLabel, systemImage: sourceIconName)
                    }
                }
                Text(endpointText)
                    .font(AppDesign.Typography.monoMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(stateDurationText)
                    if let responseTime = monitor.responseTimeMS, statusCategory == .up {
                        Text("\(responseTime) ms")
                    }
                    if let checkedAt = monitor.checkedAt {
                        Text(isLive ? "Checked \(checkedAt, style: .relative)" : "Cached · checked \(checkedAt, style: .relative)")
                    } else if !isLive {
                        Text("No confirmed check")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if statusCategory == .down, let message = monitor.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(AppDesign.Palette.warning)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            AppStatusBadge(status: isLive ? statusCategory.normalizedValue : "stale")
        }
        .padding(12)
        .appSemanticPanel(
            tint: statusColor,
            isActive: isLive,
            prominence: statusCategory == .down ? .standard : .quiet
        )
    }

    private var statusCategory: HealthMonitorStatusCategory {
        HealthMonitorStatusCategory.status(for: monitor)
    }

    private var statusColor: Color {
        guard isLive else {
            return AppDesign.Palette.stale
        }
        switch statusCategory {
        case .down:
            return AppDesign.Palette.warning
        case .unknown:
            return AppDesign.Palette.stale
        case .up:
            return AppDesign.Palette.success
        }
    }

    private var statusIconName: String {
        guard isLive else {
            return "clock.badge.exclamationmark"
        }
        switch statusCategory {
        case .down:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        case .up:
            return "checkmark.circle.fill"
        }
    }

    private var sourceLabel: String? {
        switch monitor.source {
        case "config":
            return "Config"
        case "wol":
            return "Device"
        default:
            return nil
        }
    }

    private var sourceIconName: String {
        switch monitor.source {
        case "config":
            return "lock.fill"
        case "wol":
            return "power"
        default:
            return "tag"
        }
    }

    private var endpointText: String {
        if monitor.kind == "http", let url = monitor.url {
            return url
        }
        if let host = monitor.host {
            if let port = monitor.port {
                return "\(host):\(port)"
            }
            return host
        }
        return monitor.kind
    }

    private var stateDurationText: String {
        guard let changedAt = monitor.statusChangedAt else {
            return "Not checked"
        }
        let label = statusCategory.label
        let duration = Self.shortDuration(since: changedAt)
        if isLive {
            return "\(label) \(duration)"
        }
        return "Last \(label.lowercased()) \(duration)"
    }

    private static func shortDuration(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h \(minutes % 60)m"
        }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }
}

struct WOLReadinessPanel: View {
    let title: String
    let detail: String
    let bridgeName: String
    let kind: AppStatusKind
    let metrics: [DashboardHeaderMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AppIconBubble(systemImage: "power.circle.fill", tint: kind.color, size: 36)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Spacer(minLength: 0)
                        AppStatusBadge(title: badgeTitle, kind: kind, systemImage: kind.symbolName)
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            CompactMetricPillRow(metrics: metrics)

            AppStateLine(
                title: "Bridge",
                detail: bridgeName,
                kind: kind == .warning ? .warning : .stale
            )
        }
        .padding(14)
        .appSemanticPanel(
            tint: kind.color,
            cornerRadius: AppDesign.Radius.section,
            prominence: kind == .action ? .standard : .quiet
        )
        .accessibilityElement(children: .contain)
    }

    private var badgeTitle: String {
        switch kind {
        case .success:
            return "CAN WAKE"
        case .warning:
            return "CHECK"
        case .stale:
            return "CACHED"
        case .action:
            return "CAN WAKE"
        case .destructive:
            return "SECURITY"
        }
    }
}

