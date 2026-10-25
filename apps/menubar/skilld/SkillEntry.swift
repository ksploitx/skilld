// SkillEntry.swift
// skilld — menubar app
//
// Plain Swift value type representing one skill from skills.json.
// No UI imports.

import Foundation

/// One row in skills.json — the skill catalogue.
struct SkillEntry: Codable, Identifiable, Equatable {
    /// Lowercase-kebab-case folder name (e.g. "python-expert").
    /// Used as the primary key everywhere.
    let folder: String

    /// Human-readable display name (e.g. "Python Expert").
    let name: String

    /// Short description shown in the list.
    let description: String

    /// Link to the upstream source for this skill.
    let sourceURL: String

    // Identifiable conformance — folder name is stable and unique.
    var id: String { folder }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case folder, name, description
        case sourceURL = "source_url"
    }
}
