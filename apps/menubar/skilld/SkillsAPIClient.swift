// SkillsAPIClient.swift
// skilld — menubar app
//
// URLSession-based client for the skilld backend API.
//
// Networking contract (all endpoints defined in ARCHITECTURE.md):
//   GET /skills?query=&limit=&offset=   → SkillSearchResponse
//   GET /skills/{id}                    → SkillDetail
//   GET /skills/updated-since?ts=       → [SkillSummary]
//
// The client is intentionally a plain class (no protocol) to stay simple.
// Tests inject a custom URLSession configured with MockURLProtocol.

import Foundation

// MARK: - Response models (mirror of backend Pydantic schemas)

/// Lightweight skill object returned in search results.
/// Field-for-field match with backend SkillSummary schema.
struct SkillSummary: Codable, Identifiable, Hashable {
    let id: String            // UUID string
    let name: String
    let folderName: String    // e.g. "python-expert"
    let description: String?
    let tags: [String]
    let source: String        // "github" | "skills_sh"
    let sourceURL: String     // human-readable URL for the skill
    let repo: String          // "owner/repo"
    let repoPath: String      // path inside repo to skill folder
    let commitSha: String     // pinned commit — used for install + update detection
    let updatedAt: Date

    // Convenience: derive `folder` from `folderName` for compatibility
    // with the existing SkillInstaller API which uses `.folder`.
    var folder: String { folderName }

    /// For offline fallback entries loaded from the bundled skills.json.
    static func bundled(folder: String, name: String, description: String, sourceURL: String) -> SkillSummary {
        SkillSummary(
            id: "bundled-\(folder)",
            name: name,
            folderName: folder,
            description: description,
            tags: [],
            source: "bundled",
            sourceURL: sourceURL,
            repo: "",
            repoPath: "",
            commitSha: "",
            updatedAt: .distantPast
        )
    }
}

/// Full skill detail — adds the raw SKILL.md content.
struct SkillDetail: Codable {
    let id: String
    let name: String
    let folderName: String
    let description: String?
    let tags: [String]
    let source: String
    let sourceURL: String
    let repo: String
    let repoPath: String
    let commitSha: String
    let skillMd: String
    let createdAt: Date
    let updatedAt: Date
}

/// Paginated search response envelope.
struct SkillSearchResponse: Codable {
    let results: [SkillSummary]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - API Client

final class SkillsAPIClient {

    // MARK: Properties

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    // MARK: Init

    /// Production init — uses shared URLSession and config base URL.
    convenience init() {
        self.init(session: .shared, baseURL: APIConfig.baseURL)
    }

    /// Testable init — inject a custom URLSession (e.g. with MockURLProtocol).
    init(session: URLSession, baseURL: URL) {
        self.session = session
        self.baseURL = baseURL

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Try ISO 8601 with fractional seconds first, then without
            let formatters: [ISO8601DateFormatter] = [
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }(),
                { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }(),
            ]
            for formatter in formatters {
                if let date = formatter.date(from: string) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
        }
        self.decoder = dec
    }

    // MARK: - Public API

    /// Search skills. Empty query returns recently-updated skills.
    func search(query: String = "", limit: Int = 20, offset: Int = 0) async throws -> SkillSearchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("skills"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
        ]
        guard let url = components.url else {
            throw APIError.invalidURL("search query=\(query)")
        }
        return try await perform(url: url)
    }

    /// Fetch full detail for a single skill by id.
    func get(id: String) async throws -> SkillDetail {
        let url = baseURL.appendingPathComponent("skills/\(id)")
        return try await perform(url: url)
    }

    /// Return skills updated after the given timestamp.
    /// Used to check for updates on installed skills.
    func updatedSince(timestamp: Date) async throws -> [SkillSummary] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tsString = formatter.string(from: timestamp)

        var components = URLComponents(url: baseURL.appendingPathComponent("skills/updated-since"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "ts", value: tsString)]
        guard let url = components.url else {
            throw APIError.invalidURL("updated-since ts=\(tsString)")
        }
        return try await perform(url: url)
    }

    // MARK: - Private

    private func perform<T: Decodable>(url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: APIConfig.requestTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw APIError.from(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decodingError("Non-HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8).map { $0.prefix(500) }.map(String.init)
            throw APIError.serverError(statusCode: http.statusCode, body: body)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodeError as DecodingError {
            throw APIError.decodingError(decodeError.localizedDescription)
        }
    }
}
