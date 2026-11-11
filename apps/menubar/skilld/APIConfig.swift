// APIConfig.swift
// skilld — menubar app
//
// Single source of truth for the backend base URL.
// Override for dev:
//   • Info.plist key "SkilldAPIBaseURL" (set per build configuration in Xcode)
//   • SKILLD_API_BASE_URL environment variable (convenient for quick overrides)
// Production default: https://api.skilld.sh  (change when you have a domain)
// Dev default:        http://localhost:8000

import Foundation

enum APIConfig {

    // MARK: - Base URL

    /// Resolved at startup. Priority: env var → Info.plist → hardcoded default.
    static let baseURL: URL = {
        // 1. Environment variable (highest priority — useful for CI / quick dev)
        if let envString = ProcessInfo.processInfo.environment["SKILLD_API_BASE_URL"],
           let url = URL(string: envString) {
            return url
        }
        // 2. Info.plist key (set per build configuration in Xcode)
        if let plistString = Bundle.main.object(forInfoDictionaryKey: "SkilldAPIBaseURL") as? String,
           let url = URL(string: plistString) {
            return url
        }
        // 3. Hardcoded default — http for localhost (ATS exception in Info.plist)
        return URL(string: "http://localhost:8000")!
    }()

    // MARK: - Networking constants

    /// URLSession timeout for all API calls.
    static let requestTimeout: TimeInterval = 10

    /// Milliseconds to debounce search input before firing an API call.
    static let searchDebounceMsec: Int = 300

    // MARK: - GitHub download constants

    /// Allowed hosts for skill content downloads. Any redirect to another
    /// host is rejected before the response is processed.
    static let allowedGitHubHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "codeload.github.com",
    ]

    /// Maximum uncompressed size of a skill folder (5 MB).
    static let maxSkillSizeBytes: Int = 5 * 1_024 * 1_024

    /// Maximum number of files inside a skill folder.
    static let maxSkillFileCount: Int = 100
}
