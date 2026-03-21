import Foundation

/// Configuration for the DeployRamp SDK.
public struct Config: Sendable {
    /// The public token used to authenticate with the DeployRamp API.
    public let publicToken: String

    /// The base URL for the DeployRamp flags service.
    public var baseURL: String

    /// Initial user traits for flag evaluation.
    public var traits: [String: String]

    /// Creates a new SDK configuration.
    /// - Parameters:
    ///   - publicToken: The public token for authentication.
    ///   - baseURL: The base URL for the flags service. Defaults to `https://flags.deployramp.com`.
    ///   - traits: Initial user traits. Defaults to empty.
    public init(
        publicToken: String,
        baseURL: String = "https://flags.deployramp.com",
        traits: [String: String] = [:]
    ) {
        self.publicToken = publicToken
        self.baseURL = baseURL
        self.traits = traits
    }
}
