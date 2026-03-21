import Foundation

/// HTTP client for communicating with the DeployRamp flags service.
final class ApiClient: @unchecked Sendable {
    private let baseURL: String
    private let publicToken: String
    private let session: URLSession

    init(baseURL: String, publicToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.publicToken = publicToken
        self.session = session
    }

    /// Fetches all flags from the server.
    /// - Parameters:
    ///   - userId: The current user's ID.
    ///   - traits: The current user traits.
    /// - Returns: An array of `FlagData` objects.
    func fetchFlags(userId: String, traits: [String: String]) async throws -> [FlagData] {
        guard let url = URL(string: "\(baseURL)/api/sdk/flags") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(publicToken)", forHTTPHeaderField: "Authorization")

        let payload = FlagsFetchPayload(userId: userId, traits: traits)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "Failed to fetch flags: \(statusCode)"
            ])
        }

        let flagsResponse = try JSONDecoder().decode(FlagsResponse.self, from: data)
        return flagsResponse.flags
    }

    /// Reports an error to the server. Fire-and-forget.
    /// - Parameters:
    ///   - flagName: The flag associated with the error.
    ///   - message: The error message.
    ///   - stack: Optional stack trace.
    ///   - userId: The current user's ID.
    ///   - traits: The current user traits.
    func reportError(
        flagName: String,
        message: String,
        stack: String?,
        userId: String,
        traits: [String: String]
    ) {
        guard let url = URL(string: "\(baseURL)/api/sdk/report") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(publicToken)", forHTTPHeaderField: "Authorization")

        let payload = ErrorReportPayload(
            flagName: flagName,
            message: message,
            stack: stack,
            userId: userId,
            traits: traits
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            return
        }

        // Fire-and-forget
        let task = session.dataTask(with: request) { _, _, _ in }
        task.resume()
    }
}
