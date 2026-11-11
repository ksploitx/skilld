// APIError.swift
// skilld — menubar app
//
// Typed errors surfaced by SkillsAPIClient. Each case maps to a user-readable
// description shown in the UI.

import Foundation

enum APIError: Error, LocalizedError {

    /// No network connection (device offline or DNS failure).
    case offline

    /// The request timed out before the server responded.
    case timeout

    /// The server returned an HTTP error status.
    case serverError(statusCode: Int, body: String?)

    /// The JSON response could not be decoded into the expected model.
    case decodingError(String)

    /// A URL could not be constructed from the given parameters.
    case invalidURL(String)

    // MARK: LocalizedError

    var errorDescription: String? {
        switch self {
        case .offline:
            return "You appear to be offline. Showing cached skills."
        case .timeout:
            return "The server took too long to respond. Check your connection."
        case .serverError(let code, let body):
            let detail = body.map { " — \($0)" } ?? ""
            return "Server error \(code)\(detail)"
        case .decodingError(let detail):
            return "Unexpected response from server: \(detail)"
        case .invalidURL(let detail):
            return "Internal error: could not build URL — \(detail)"
        }
    }

    // MARK: Factory

    /// Map a URLError to the appropriate APIError case.
    static func from(_ urlError: URLError) -> APIError {
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .resourceUnavailable:
            return .offline
        default:
            return .offline
        }
    }
}
