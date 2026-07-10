import Foundation
import PopRocketKit
import SwiftUI

enum DashboardFocusField: Hashable {
    case command
}

enum DashboardTab: Hashable {
    case overview
    case health
    case actions
    case activity
    case settings

    var title: String {
        switch self {
        case .overview:
            return "Home"
        case .health:
            return "Monitors"
        case .actions:
            return "Actions"
        case .activity:
            return "Activity"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "gauge.with.dots.needle.33percent"
        case .health:
            return "waveform.path.ecg"
        case .actions:
            return "bolt.circle"
        case .activity:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}

enum DashboardActionMode: Hashable {
    case wake
    case run

    var title: String {
        switch self {
        case .wake:
            return "Wake"
        case .run:
            return "Run"
        }
    }

    var systemImage: String {
        switch self {
        case .wake:
            return "power"
        case .run:
            return "terminal"
        }
    }
}

struct DashboardDeepLink {
    let tab: DashboardTab
    let actionMode: DashboardActionMode?

    init?(url: URL) {
        let route = Self.route(for: url)
        guard let tab = Self.tab(for: route) else {
            return nil
        }
        self.tab = tab
        self.actionMode = Self.actionMode(for: url, route: route)
    }

    private static func route(for url: URL) -> String {
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        if !host.isEmpty {
            return host.lowercased()
        }
        return url.path
            .split(separator: "/")
            .first
            .map { String($0).lowercased() } ?? ""
    }

    private static func tab(for route: String) -> DashboardTab? {
        switch route {
        case "home", "status", "dashboard":
            return .overview
        case "monitors", "monitor", "health":
            return .health
        case "actions", "action", "wake", "run", "commands", "command":
            return .actions
        case "activity", "audit", "history", "log":
            return .activity
        case "settings", "bridges", "bridge", "widgets", "feedback":
            return .settings
        default:
            return nil
        }
    }

    private static func actionMode(for url: URL, route: String) -> DashboardActionMode? {
        let queryMode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "mode" || $0.name == "action" }?
            .value?
            .lowercased()
        let pathComponents = url.path.split(separator: "/")
        let pathMode = (url.host?.isEmpty == false ? pathComponents.first : pathComponents.dropFirst().first)
            .map { String($0).lowercased() }
        switch queryMode ?? pathMode ?? route {
        case "wake", "wol", "device", "devices":
            return .wake
        case "run", "command", "commands", "tile", "tiles":
            return .run
        default:
            return nil
        }
    }
}

enum CommandEditorFocusField: Hashable {
    case name
    case command
}

enum HealthMonitorEditorFocusField: Hashable {
    case name
    case host
    case port
    case url
    case timeoutSeconds
}

enum WOLTargetEditorFocusField: Hashable {
    case name
    case mac
    case ipAddress
    case broadcastIP
    case udpPort
}

struct TargetEditorState: Identifiable {
    let id = UUID()
    let target: WOLTarget?
}

struct HealthMonitorEditorState: Identifiable {
    let id = UUID()
    let monitor: HealthMonitor?
}

struct CommandEditorState: Identifiable {
    let id = UUID()
    let shortcut: CommandShortcut?
    let initialCommand: String
    let clearComposerOnSave: Bool
}

struct DashboardFeedbackNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    let progress: Bool
}

enum FeedbackAnimationDirection {
    case entering
    case exiting
}

enum DashboardDesign {
    static let pagePadding = AppDesign.Spacing.page
    static let sectionSpacing = AppDesign.Spacing.section
    static let sectionCornerRadius = AppDesign.Radius.section
    static let controlSpacing = AppDesign.Spacing.control
    static let tileMinimumHeight = AppDesign.Size.actionTileMinimumHeight
    static let background = AppDesign.background
    static let sectionFill = AppDesign.sectionFill
    static let sectionStroke = AppDesign.sectionStroke
    static let disabledOpacity = AppDesign.disabledOpacity
}
