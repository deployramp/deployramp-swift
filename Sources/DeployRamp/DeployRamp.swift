import Foundation

/// Main entry point for the DeployRamp SDK.
///
/// ```swift
/// try await DeployRamp.initialize(Config(publicToken: "pk_live_abc123"))
///
/// if DeployRamp.flag("new-checkout") {
///     // new checkout flow
/// }
///
/// DeployRamp.close()
/// ```
public final class DeployRamp: @unchecked Sendable {

    // MARK: - Singleton

    private static let lock = NSLock()
    private static var client: ApiClient?
    private static var cache: FlagCache?
    private static var currentTraits: [String: String] = [:]
    private static var userId: String?

    private init() {}

    // MARK: - User ID

    private static func getUserId() -> String {
        lock.lock()
        defer { lock.unlock() }

        if let existing = userId {
            return existing
        }
        let id = UUID().uuidString
        userId = id
        return id
    }

    // MARK: - Hash function (matches JS SDK)

    static func hashKey(_ input: String) -> Int {
        var h: Int32 = 0
        for scalar in input.unicodeScalars {
            h = (h &<< 5) &- h &+ Int32(scalar.value)
        }
        return Int(abs(h)) % 100
    }

    // MARK: - Condition matching

    static func matchCondition(_ condition: TraitCondition, traits: [String: String]) -> Bool {
        switch condition.type {
        case "match":
            guard let key = condition.traitKey, let expected = condition.traitValue else {
                return false
            }
            return traits[key] == expected
        case "and":
            return condition.conditions?.allSatisfy { matchCondition($0, traits: traits) } ?? true
        case "or":
            return condition.conditions?.contains { matchCondition($0, traits: traits) } ?? false
        default:
            return false
        }
    }

    // MARK: - Trait merging

    private static func mergeTraits(
        _ base: [String: String],
        overrides: [String: String]?
    ) -> [String: String] {
        guard let overrides = overrides, !overrides.isEmpty else {
            return base
        }
        return base.merging(overrides) { _, new in new }
    }

    private static func setInitialState(client apiClient: ApiClient, cache flagCache: FlagCache, traits: [String: String]) {
        lock.lock()
        client = apiClient
        cache = flagCache
        currentTraits = traits
        lock.unlock()
    }

    // MARK: - Public API

    /// Initialises the DeployRamp SDK. Fetches flags from the server.
    ///
    /// - Parameter config: The SDK configuration.
    public static func initialize(_ config: Config) async throws {
        let baseURL = config.baseURL.hasSuffix("/")
            ? String(config.baseURL.dropLast())
            : config.baseURL

        let apiClient = ApiClient(baseURL: baseURL, publicToken: config.publicToken)
        let flagCache = FlagCache()

        setInitialState(client: apiClient, cache: flagCache, traits: config.traits)

        do {
            let flags = try await apiClient.fetchFlags(
                userId: getUserId(),
                traits: config.traits
            )
            flagCache.setFlags(flags)

            // Build WebSocket URL
            let wsProto = baseURL.hasPrefix("https") ? "wss" : "ws"
            let host = baseURL
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            let token = config.publicToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.publicToken
            let wsURL = URL(string: "\(wsProto)://\(host)/ws?token=\(token)")!
            flagCache.connectWebSocket(url: wsURL)
        } catch {
            print("[deployramp] Failed to initialize: \(error)")
        }
    }

    /// Replaces the current global traits.
    public static func setTraits(_ traits: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        currentTraits = traits
    }

    /// Evaluates a feature flag.
    ///
    /// - Parameters:
    ///   - name: The flag name.
    ///   - traitOverrides: Optional trait overrides merged on top of global traits.
    /// - Returns: `true` if the flag is active for the current user.
    public static func flag(_ name: String, traitOverrides: [String: String]? = nil) -> Bool {
        lock.lock()
        let flagCache = cache
        let traits = mergeTraits(currentTraits, overrides: traitOverrides)
        lock.unlock()

        guard let flagCache = flagCache else { return false }

        guard let f = flagCache.getFlag(name) else {
            queueEvaluation(name: name, result: false, traitOverrides: traitOverrides)
            return false
        }
        guard f.enabled else {
            queueEvaluation(name: name, result: false, traitOverrides: traitOverrides)
            return false
        }

        let uid = getUserId()

        // Check segments for trait-based rollout
        if let segments = f.segments, !segments.isEmpty {
            for segment in segments {
                if matchCondition(segment.condition, traits: traits) {
                    // Sticky check
                    if segment.sticky,
                       let sticky = f.stickyAssignments,
                       sticky.contains(segment.segmentId) {
                        queueEvaluation(name: name, result: true, traitOverrides: traitOverrides)
                        return true
                    }

                    let bucket = hashKey("\(name):\(uid):\(segment.segmentId)")
                    let result = bucket < segment.rolloutPercentage
                    queueEvaluation(name: name, result: result, traitOverrides: traitOverrides)
                    return result
                }
            }
        }

        // Default: use top-level rollout percentage
        if f.rolloutPercentage >= 100 {
            queueEvaluation(name: name, result: true, traitOverrides: traitOverrides)
            return true
        }
        if f.rolloutPercentage <= 0 {
            queueEvaluation(name: name, result: false, traitOverrides: traitOverrides)
            return false
        }

        let bucket = hashKey("\(name):\(uid)")
        let result = bucket < f.rolloutPercentage
        queueEvaluation(name: name, result: result, traitOverrides: traitOverrides)
        return result
    }

    private static func queueEvaluation(
        name: String,
        result: Bool,
        traitOverrides: [String: String]?
    ) {
        lock.lock()
        let flagCache = cache
        let traits = mergeTraits(currentTraits, overrides: traitOverrides)
        lock.unlock()

        guard let flagCache = flagCache else { return }

        let event = EvaluationEvent(
            flagName: name,
            result: result,
            traits: traits,
            userId: getUserId(),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000)
        )
        flagCache.queueEvaluation(event)
    }

    /// Reports an error to DeployRamp. Fire-and-forget.
    ///
    /// - Parameters:
    ///   - error: The error to report.
    ///   - flagName: The flag associated with the error (optional).
    ///   - traitOverrides: Optional trait overrides.
    public static func report(
        _ error: Error,
        flagName: String? = nil,
        traitOverrides: [String: String]? = nil
    ) {
        lock.lock()
        let apiClient = client
        let traits = mergeTraits(currentTraits, overrides: traitOverrides)
        lock.unlock()

        guard let apiClient = apiClient else { return }

        apiClient.reportError(
            flagName: flagName ?? "unknown",
            message: error.localizedDescription,
            stack: String(describing: error),
            userId: getUserId(),
            traits: traits
        )
    }

    /// Shuts down the SDK, flushing pending evaluations and closing connections.
    public static func close() {
        lock.lock()
        let flagCache = cache
        cache = nil
        client = nil
        currentTraits = [:]
        userId = nil
        lock.unlock()

        flagCache?.close()
    }
}
