// SkillEntry.swift
// skilld — menubar app
//
// Legacy type kept only for backward-compatibility with the existing
// SkillInstaller.install(skill:sourceFolder:) signature and
// SkillInstallerTests.swift test helpers.
//
// New code should use SkillSummary (from SkillsAPIClient.swift) for
// all API-backed operations.

import Foundation

/// Minimal legacy struct used only by SkillInstaller's bundled-install path
/// and the test suite. For the full API-backed model, use `SkillSummary`.
struct SkillEntry: Codable, Identifiable, Equatable, Sendable {
    /// Lowercase-kebab-case folder name (e.g. "python-expert").
    let folder: String
    /// Human-readable display name.
    let name: String
    /// Short description.
    let description: String
    /// Source URL.
    let sourceURL: String

    // Identifiable — folder is stable and unique
    var id: String { folder }

    enum CodingKeys: String, CodingKey {
        case folder, name, description
        case sourceURL = "source_url"
    }
}
