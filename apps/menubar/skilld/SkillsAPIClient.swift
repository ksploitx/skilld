// SkillsAPIClient.swift
// skilld — menubar app
//
// Plain Swift HTTP client for the skilld backend API.
// Uses URLSession directly — no third-party dependencies.
// All errors are typed via SkillsAPIError for clear UI messaging.

import Foundation

// MARK: - Error types

enum SkillsAPIError: Error, LocalizedError, Equatable {
    case offline
    case serverError(statusCode: Int, body: String)
    case decodingError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .offline:
            return "Cannot reach the skilld server. Showing offline catalogue."
        case .serverError(let code, let body):
            return "Server error (\(code)): \(body)"
        case .decodingError(let detail):
            return "Failed to decode server response: \(detail)"
        case .timeout:
            return "Request timed out. Check your connection and try again."
        }
    }
}

// MARK: - Protocol for testability

/// Abstraction over URLSession so tests can inject a mock.
protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - API response models (match backend Pydantic schemas)

/// Matches backend `SkillSummary` — returned in search results.
struct APISkillSummary: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let folderName: String
    let description: String?
    let tags: [String]
    let source: String
    let sourceURL: String
    let repo: String
    let repoPath: String
    let commitSHA: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, tags, source, repo
        case folderName = "folder_name"
        case sourceURL = "source_url"
        case repoPath = "repo_path"
        case commitSHA = "commit_sha"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Matches backend `SkillDetail` — includes full SKILL.md text.
struct APISkillDetail: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let folderName: String
    let description: String?
    let tags: [String]
    let source: String
    let sourceURL: String
    let repo: String
    let repoPath: String
    let commitSHA: String
    let skillMD: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, tags, source, repo
        case folderName = "folder_name"
        case sourceURL = "source_url"
        case repoPath = "repo_path"
        case commitSHA = "commit_sha"
        case skillMD = "skill_md"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Matches backend `SkillSearchResponse` — paginated envelope.
struct APISkillSearchResponse: Codable, Equatable, Sendable {
    let total: Int
    let limit: Int
    let offset: Int
    let results: [APISkillSummary]
}

// MARK: - SkillsAPIClient

/// HTTP client for the skilld backend REST API.
/// Thread-safe and Sendable. Stateless — no caching here.
final class SkillsAPIClient: Sendable {

    private let baseURL: URL
    private let session: URLSessionProtocol
    private let decoder: JSONDecoder

    // MARK: Init

    /// Production init.
    convenience init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeoutInterval
        config.timeoutIntervalForResource = APIConfig.timeoutInterval
        self.init(
            baseURL: APIConfig.baseURL,
            session: URLSession(configuration: config)
        )
    }

    /// Testable init — inject base URL and session.
    init(baseURL: URL, session: URLSessionProtocol) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: Endpoints

    /// `GET /skills?query=&limit=&offset=`
    func search(query: String = "", limit: Int = 20, offset: Int = 0) async throws(SkillsAPIError) -> APISkillSearchResponse {
        var components = URLComponents(url: baseURL.appending(path: "/skills"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components.url else {
            throw .decodingError("Invalid URL")
        }
        return try await perform(URLRequest(url: url))
    }

    /// `GET /skills/{id}`
    func get(id: String) async throws(SkillsAPIError) -> APISkillDetail {
        let url = baseURL.appending(path: "/skills/\(id)")
        return try await perform(URLRequest(url: url))
    }

    /// `GET /skills/updated-since?ts=`
    func updatedSince(ts: Date) async throws(SkillsAPIError) -> [APISkillSummary] {
        let iso = ISO8601DateFormatter().string(from: ts)
        var components = URLComponents(url: baseURL.appending(path: "/skills/updated-since"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ts", value: iso),
        ]
        guard let url = components.url else {
            throw .decodingError("Invalid URL")
        }
        return try await perform(URLRequest(url: url))
    }

    // MARK: Private

    private func perform<T: Decodable>(_ request: URLRequest) async throws(SkillsAPIError) -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorTimedOut {
                throw .timeout
            }
            // NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost,
            // NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost
            throw .offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw .offline
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw .serverError(statusCode: http.statusCode, body: body)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw .decodingError(error.localizedDescription)
        }
    }
}
