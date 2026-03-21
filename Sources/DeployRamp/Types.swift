import Foundation

// MARK: - Trait Condition

/// A recursive condition tree for matching user traits. Supports "match", "and", and "or" types.
public struct TraitCondition: Codable, Equatable, Sendable {
    public let type: String
    public let traitKey: String?
    public let traitValue: String?
    public let conditions: [TraitCondition]?

    public init(type: String, traitKey: String? = nil, traitValue: String? = nil, conditions: [TraitCondition]? = nil) {
        self.type = type
        self.traitKey = traitKey
        self.traitValue = traitValue
        self.conditions = conditions
    }
}

// MARK: - Flag Segment

/// A rollout segment: applies a strategy to users matching a condition.
public struct FlagSegment: Codable, Equatable, Sendable {
    public let segmentId: String
    public let condition: TraitCondition
    public let rolloutPercentage: Int
    public let sticky: Bool

    public init(segmentId: String, condition: TraitCondition, rolloutPercentage: Int, sticky: Bool) {
        self.segmentId = segmentId
        self.condition = condition
        self.rolloutPercentage = rolloutPercentage
        self.sticky = sticky
    }
}

// MARK: - Flag Data

/// Represents a feature flag returned from the server.
public struct FlagData: Codable, Equatable, Sendable {
    public let name: String
    public let enabled: Bool
    public let rolloutPercentage: Int
    public let value: String?
    public let segments: [FlagSegment]?
    public let stickyAssignments: [String]?

    public init(
        name: String,
        enabled: Bool,
        rolloutPercentage: Int,
        value: String? = nil,
        segments: [FlagSegment]? = nil,
        stickyAssignments: [String]? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.rolloutPercentage = rolloutPercentage
        self.value = value
        self.segments = segments
        self.stickyAssignments = stickyAssignments
    }
}

// MARK: - Evaluation Event

/// An evaluation event sent to the backend for analytics.
struct EvaluationEvent: Codable, Sendable {
    let type: String
    let flagName: String
    let result: Bool
    let traits: [String: String]
    let userId: String
    let timestamp: Int64

    init(flagName: String, result: Bool, traits: [String: String], userId: String, timestamp: Int64) {
        self.type = "evaluation"
        self.flagName = flagName
        self.result = result
        self.traits = traits
        self.userId = userId
        self.timestamp = timestamp
    }
}

// MARK: - WebSocket Message

/// A message sent or received over the WebSocket connection.
struct WsMessage: Codable, Sendable {
    let type: String
    let flags: [FlagData]?
    let evaluations: [EvaluationEvent]?

    init(type: String, flags: [FlagData]? = nil, evaluations: [EvaluationEvent]? = nil) {
        self.type = type
        self.flags = flags
        self.evaluations = evaluations
    }
}

// MARK: - API Response

/// Response from the /api/sdk/flags endpoint.
struct FlagsResponse: Codable {
    let flags: [FlagData]
}

/// Payload sent to the /api/sdk/report endpoint.
struct ErrorReportPayload: Codable {
    let flagName: String
    let message: String
    let stack: String?
    let userId: String?
    let traits: [String: String]?
}

/// Payload sent to the /api/sdk/flags endpoint.
struct FlagsFetchPayload: Codable {
    let userId: String?
    let traits: [String: String]?
}
