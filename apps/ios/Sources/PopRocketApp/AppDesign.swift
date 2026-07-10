import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum AppDesign {
    enum Palette {
        // Domain accents identify where a control belongs.
        static let action = Color(lightHex: 0x2563EB, darkHex: 0x60A5FA)
        static let bridge = Color(lightHex: 0x0891B2, darkHex: 0x22D3EE)
        static let health = Color(lightHex: 0x16A34A, darkHex: 0x4ADE80)
        static let wake = Color(lightHex: 0x7C3AED, darkHex: 0xA78BFA)
        static let command = Color(lightHex: 0x4F46E5, darkHex: 0x818CF8)
        static let activity = Color(lightHex: 0x0D9488, darkHex: 0x2DD4BF)
        static let widget = Color(lightHex: 0x059669, darkHex: 0x34D399)

        // Operational states identify what needs attention.
        static let success = Color(lightHex: 0x16A34A, darkHex: 0x4ADE80)
        static let warning = Color(lightHex: 0xD97706, darkHex: 0xFBBF24)
        static let stale = Color(lightHex: 0x64748B, darkHex: 0x94A3B8)
        static let destructive = Color(lightHex: 0xDC2626, darkHex: 0xF87171)
        static let cached = stale
        static let locked = stale
    }

    enum Spacing {
        static let page: CGFloat = 18
        static let section: CGFloat = 16
        static let content: CGFloat = 16
        static let control: CGFloat = 12
        static let fieldPadding: CGFloat = 13
    }

    enum Radius {
        static let section: CGFloat = 10
        static let panel: CGFloat = 8
    }

    enum Typography {
        static let sectionTitle = Font.title3.weight(.semibold)
        static let dashboardSectionTitle = Font.headline.weight(.semibold)
        static let dashboardMetricValue = Font.subheadline.weight(.semibold)
        static let panelTitle = Font.subheadline.weight(.semibold)
        static let controlLabel = Font.caption.weight(.semibold)
        static let metadata = Font.caption2.weight(.medium)
        static let monoMetadata = Font.system(.caption2, design: .monospaced)
    }

    enum Motion {
        static let feedbackIn = Animation.snappy(duration: 0.22)
        static let feedbackOut = Animation.snappy(duration: 0.18)
        static let press = Animation.snappy(duration: 0.14)
        static let stateChange = Animation.snappy(duration: 0.22)
    }

    enum Size {
        static let actionTileMinimumHeight: CGFloat = 128
        static let iconButton: CGFloat = 44
    }

    static var background: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    static var sectionFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.secondary.opacity(0.06)
        #endif
    }

    static var panelFill: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        Color.secondary.opacity(0.08)
        #endif
    }

    static let sectionStroke = Color.secondary.opacity(0.12)
    static let panelStroke = Color.secondary.opacity(0.18)
    static let codeBlockFill = Palette.stale.opacity(0.08)
    static let disabledOpacity = 0.55

    static func statusColor(_ status: String) -> Color {
        AppStatusKind(status: status).color
    }

    static func statusLabel(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed":
            return "Completed"
        case "request failed":
            return "Failed"
        case "stale":
            return "Cached"
        case "":
            return "Unknown"
        default:
            return status
        }
    }
}

enum AppFormat {
    enum DurationPrecision {
        case largestUnit
        case remainder
    }

    static func relativeShort(_ date: Date, relativeTo referenceDate: Date = Date()) -> String {
        relativeShortFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func relativeAbbreviated(_ date: Date, relativeTo referenceDate: Date = Date()) -> String {
        relativeAbbreviatedFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    static func shortDuration(seconds rawSeconds: Int, precision: DurationPrecision = .remainder) -> String {
        let seconds = max(0, rawSeconds)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            switch precision {
            case .largestUnit:
                return "\(hours)h"
            case .remainder:
                return "\(hours)h \(minutes % 60)m"
            }
        }
        let days = hours / 24
        switch precision {
        case .largestUnit:
            return "\(days)d"
        case .remainder:
            return "\(days)d \(hours % 24)h"
        }
    }

    private static let relativeShortFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let relativeAbbreviatedFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    init(lightHex: UInt32, darkHex: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
        #else
        self.init(hex: lightHex)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
#endif

enum AppStatusKind: Equatable {
    case success
    case warning
    case stale
    case action
    case destructive

    init(status: String) {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "accepted", "fresh", "up", "completed", "connected", "online", "healthy", "ok", "sent":
            self = .success
        case "down", "failed", "request failed", "denied", "error", "offline", "unhealthy", "unavailable", "timeout", "timed out":
            self = .warning
        case "delete", "deleted", "destructive", "security":
            self = .destructive
        default:
            self = .stale
        }
    }

    var color: Color {
        switch self {
        case .success:
            return AppDesign.Palette.success
        case .warning:
            return AppDesign.Palette.warning
        case .stale:
            return AppDesign.Palette.stale
        case .action:
            return AppDesign.Palette.action
        case .destructive:
            return AppDesign.Palette.destructive
        }
    }

    var symbolName: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .action:
            return "bolt.circle.fill"
        case .destructive:
            return "trash.circle.fill"
        }
    }
}

enum AppSurfaceProminence {
    case quiet
    case standard
    case strong

    var fillOpacity: Double {
        switch self {
        case .quiet:
            return 0.070
        case .standard:
            return 0.110
        case .strong:
            return 0.160
        }
    }

    var strokeOpacity: Double {
        switch self {
        case .quiet:
            return 0.24
        case .standard:
            return 0.36
        case .strong:
            return 0.46
        }
    }

    var railOpacity: Double {
        switch self {
        case .quiet:
            return 0.76
        case .standard:
            return 0.90
        case .strong:
            return 0.96
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .quiet:
            return 0.025
        case .standard:
            return 0.040
        case .strong:
            return 0.055
        }
    }
}

struct AppSemanticPanelModifier: ViewModifier {
    let tint: Color
    var isActive = true
    var cornerRadius = AppDesign.Radius.panel
    var prominence = AppSurfaceProminence.standard
    var showsRail = true

    func body(content: Content) -> some View {
        let resolvedTint = isActive ? tint : AppDesign.Palette.stale
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppDesign.panelFill)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                resolvedTint.opacity(fillOpacity * 1.20),
                                resolvedTint.opacity(fillOpacity * 0.56)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(resolvedTint.opacity(strokeOpacity), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if showsRail {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(resolvedTint.opacity(railOpacity))
                        .frame(width: 4)
                        .padding(.vertical, 10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: resolvedTint.opacity(shadowOpacity),
                radius: isActive ? 12 : 7,
                x: 0,
                y: isActive ? 5 : 3
            )
    }

    private var fillOpacity: Double {
        isActive ? prominence.fillOpacity : 0.035
    }

    private var strokeOpacity: Double {
        isActive ? prominence.strokeOpacity : 0.14
    }

    private var railOpacity: Double {
        isActive ? prominence.railOpacity : 0.32
    }

    private var shadowOpacity: Double {
        isActive ? prominence.shadowOpacity : 0.014
    }
}

struct AppActionSurfaceModifier: ViewModifier {
    let tint: Color
    var isEnabled = true

    func body(content: Content) -> some View {
        let resolvedTint = isEnabled ? tint : AppDesign.Palette.stale
        content
            .background {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .fill(AppDesign.panelFill)
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                resolvedTint.opacity(isEnabled ? 0.145 : 0.050),
                                resolvedTint.opacity(isEnabled ? 0.075 : 0.030)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .stroke(resolvedTint.opacity(isEnabled ? 0.52 : 0.22), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(resolvedTint.opacity(isEnabled ? 0.96 : 0.38))
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .shadow(
                color: resolvedTint.opacity(isEnabled ? 0.070 : 0.018),
                radius: isEnabled ? 13 : 6,
                x: 0,
                y: isEnabled ? 6 : 3
            )
    }
}

struct AppSection<Content: View>: View {
    let title: String
    var subtitle: String = ""
    let systemImage: String
    var tint: Color = AppDesign.Palette.action
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                    if let subtitleText {
                        Text(subtitleText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var subtitleText: String? {
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AppStatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.17))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

struct AppStatusBadge: View {
    let title: String
    let kind: AppStatusKind
    var systemImage: String?

    init(title: String, kind: AppStatusKind, systemImage: String? = nil) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
    }

    init(status: String) {
        self.title = AppDesign.statusLabel(status).uppercased()
        self.kind = AppStatusKind(status: status)
        self.systemImage = nil
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(kind.color.opacity(0.17), in: Capsule())
        .foregroundStyle(kind.color)
    }
}

struct AppStateLine: View {
    let title: String
    let detail: String?
    let kind: AppStatusKind

    init(title: String, detail: String? = nil, kind: AppStatusKind) {
        self.title = title
        self.detail = detail
        self.kind = kind
    }

    init(status: String, detail: String? = nil) {
        self.title = AppDesign.statusLabel(status)
        self.detail = detail
        self.kind = AppStatusKind(status: status)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(kind.color)
                .frame(width: 7, height: 7)
            Text(title)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .lineLimit(1)
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(kind.color)
        .accessibilityElement(children: .combine)
    }
}

struct AppPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(pressedScale(isPressed: configuration.isPressed))
            .brightness(configuration.isPressed && isEnabled ? -0.018 : 0)
            .shadow(
                color: isEnabled ? tint.opacity(configuration.isPressed ? 0.14 : 0.065) : .clear,
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 5
            )
            .animation(reduceMotion ? nil : AppDesign.Motion.press, value: configuration.isPressed)
    }

    private func pressedScale(isPressed: Bool) -> CGFloat {
        guard isPressed, isEnabled, !reduceMotion else {
            return 1
        }
        return 0.965
    }
}

struct AppActionButton: View {
    let title: String
    let systemImage: String
    let kind: AppStatusKind
    var isRunning = false
    var isEnabled = true
    var disabledReason: String?
    var runningReason: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isEnabled ? systemImage : "lock.fill")
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(AppPressButtonStyle(tint: pressTint, isEnabled: isEnabled && !isRunning))
        .disabled(!isEnabled || isRunning)
        .opacity(isEnabled || isRunning ? 1 : AppDesign.disabledOpacity)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityState)
        .accessibilityHint(accessibilityHint)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return AppDesign.Palette.stale
        }
        switch kind {
        case .success, .warning, .destructive, .action:
            return kind.color
        case .stale:
            return AppDesign.Palette.stale
        }
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return AppDesign.Palette.stale.opacity(0.08)
        }
        return kind.color.opacity(0.22)
    }

    private var borderColor: Color {
        if !isEnabled {
            return AppDesign.panelStroke
        }
        return kind.color.opacity(0.32)
    }

    private var pressTint: Color {
        isEnabled ? kind.color : AppDesign.Palette.stale
    }

    private var accessibilityState: String {
        if isRunning {
            return "In progress"
        }
        return isEnabled ? "Available" : "Unavailable"
    }

    private var accessibilityHint: String {
        if isRunning {
            return runningReason ?? "Operation in progress."
        }
        if !isEnabled {
            return disabledReason ?? "Unavailable."
        }
        return ""
    }
}

struct AppIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var tint: Color = AppDesign.Palette.action
    var isRunning = false
    var isEnabled = true
    var disabledReason: String?
    var runningReason: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppIconButtonLabel(
                systemImage: systemImage,
                tint: tint,
                isRunning: isRunning,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(AppPressButtonStyle(tint: isEnabled ? tint : AppDesign.Palette.stale, isEnabled: isEnabled && !isRunning))
        .disabled(!isEnabled || isRunning)
        .opacity(isEnabled || isRunning ? 1 : AppDesign.disabledOpacity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityState)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityState: String {
        if isRunning {
            return "In progress"
        }
        return isEnabled ? "Available" : "Unavailable"
    }

    private var accessibilityHint: String {
        if isRunning {
            return runningReason ?? "Operation in progress."
        }
        if !isEnabled {
            return disabledReason ?? "Unavailable."
        }
        return ""
    }
}

struct AppCompactActionButton: View {
    let title: String
    let systemImage: String
    var accessibilityLabel: String?
    let kind: AppStatusKind
    var isRunning = false
    var isEnabled = true
    var disabledReason: String?
    var runningReason: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isEnabled ? systemImage : "lock.fill")
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .font(AppDesign.Typography.controlLabel)
            .frame(minHeight: AppDesign.Size.iconButton)
            .padding(.horizontal, 11)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(AppPressButtonStyle(tint: pressTint, isEnabled: isEnabled && !isRunning))
        .disabled(!isEnabled || isRunning)
        .opacity(isEnabled || isRunning ? 1 : AppDesign.disabledOpacity)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(accessibilityState)
        .accessibilityHint(accessibilityHint)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return AppDesign.Palette.stale
        }
        return kind.color
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return AppDesign.Palette.stale.opacity(0.08)
        }
        return kind.color.opacity(0.22)
    }

    private var borderColor: Color {
        if !isEnabled {
            return AppDesign.panelStroke
        }
        return kind.color.opacity(0.32)
    }

    private var pressTint: Color {
        isEnabled ? kind.color : AppDesign.Palette.stale
    }

    private var accessibilityState: String {
        if isRunning {
            return "In progress"
        }
        return isEnabled ? "Available" : "Unavailable"
    }

    private var accessibilityHint: String {
        if isRunning {
            return runningReason ?? "Operation in progress."
        }
        if !isEnabled {
            return disabledReason ?? "Unavailable."
        }
        return ""
    }
}

struct AppIconButtonLabel: View {
    let systemImage: String
    var tint: Color = AppDesign.Palette.action
    var isRunning = false
    var isEnabled = true

    var body: some View {
        Group {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isEnabled ? systemImage : "lock.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(width: AppDesign.Size.iconButton, height: AppDesign.Size.iconButton)
        .foregroundStyle(isEnabled ? tint : AppDesign.Palette.stale)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.Radius.panel, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var borderColor: Color {
        if !isEnabled {
            return AppDesign.panelStroke
        }
        return tint.opacity(0.32)
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return AppDesign.Palette.stale.opacity(0.08)
        }
        return tint.opacity(0.20)
    }
}

struct AppIconBubble: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.20), in: Circle())
            .overlay {
                Circle()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
    }
}

struct AppNoticeRow: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var progress = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if progress {
                ProgressView()
                    .frame(width: 24)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct AppEmptyState: View {
    let title: String
    let message: String
    let systemImage: String
    var tint: Color = AppDesign.Palette.stale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .appSemanticPanel(tint: tint, prominence: .quiet)
    }
}

struct AppTransientNotice: View {
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
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint, in: Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Radius.section, style: .continuous)
                .stroke(AppDesign.sectionStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
    }
}

struct AppDisabledReasonRow: View {
    let reason: String
    var systemImage = "lock.fill"

    var body: some View {
        Label(reason, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

struct AppFieldLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

extension View {
    func appPanel(cornerRadius: CGFloat = AppDesign.Radius.panel) -> some View {
        background(AppDesign.panelFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppDesign.panelStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func appSemanticPanel(
        tint: Color,
        isActive: Bool = true,
        cornerRadius: CGFloat = AppDesign.Radius.panel,
        prominence: AppSurfaceProminence = .standard,
        showsRail: Bool = true
    ) -> some View {
        modifier(
            AppSemanticPanelModifier(
                tint: tint,
                isActive: isActive,
                cornerRadius: cornerRadius,
                prominence: prominence,
                showsRail: showsRail
            )
        )
    }

    func appActionSurface(tint: Color, isEnabled: Bool = true) -> some View {
        modifier(AppActionSurfaceModifier(tint: tint, isEnabled: isEnabled))
    }

    func appField() -> some View {
        padding(AppDesign.Spacing.fieldPadding)
            .appPanel()
    }

    func appPage() -> some View {
        background(AppDesign.background.ignoresSafeArea())
    }
}
