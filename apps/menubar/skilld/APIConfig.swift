// APIConfig.swift
// skilld — menubar app
//
// Single source of truth for the backend API base URL.
// Override via Info.plist key "SkilldAPIBaseURL" or environment
// variable SKILLD_API_BASE_URL for development builds.

import Foundation

enum APIConfig {
    /// Default backend URL used during local development.
    private static let defaultBaseURL = "http://localhost:8000"

    /// Resolved base URL, checked in order:
    /// 1. Environment variable `SKILLD_API_BASE_URL`
    /// 2. Info.plist key `SkilldAPIBaseURL`
    /// 3. Built-in default (`http://localhost:8000`)
    static var baseURL: URL {
        if let env = ProcessInfo.processInfo.environment["SKILLD_API_BASE_URL"],
           let url = URL(string: env) {
            return url
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "SkilldAPIBaseURL") as? String,
           let url = URL(string: plist) {
            return url
        }
        return URL(string: defaultBaseURL)!
    }

    /// Request timeout in seconds.
    static let timeoutInterval: TimeInterval = 10

    // MARK: - GitHub domain allowlist (for install downloads)

    /// Only these hosts are allowed for downloading skill content.
    static let allowedGitHubHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "codeload.github.com",
    ]
}
