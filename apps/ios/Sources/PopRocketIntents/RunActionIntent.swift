import AppIntents
import PopRocketKit

public struct RunActionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Run PopRocket Action"
    public static var description = IntentDescription("Runs a scoped PopRocket action.")

    @Parameter(title: "Action ID")
    public var actionID: String

    @Parameter(title: "Event ID")
    public var eventID: String?

    public init() {
        self.actionID = "ack"
        self.eventID = nil
    }

    public init(actionID: String, eventID: String?) {
        self.actionID = actionID
        self.eventID = eventID
    }

    public func perform() async throws -> some IntentResult {
        try await NotificationActionRouter().route(actionID: actionID, eventID: eventID, confirmed: actionID != "ack")
        return .result()
    }
}
