// SkillEntry.swift
// skilld — menubar app
//
// Value type representing one skill — decoded from the backend API
// or from the bundled skills.json offline fallback.
// No UI imports.

import Foundation

/// One row in the skill catalogue.
/// Fields mirror the backend `SkillSummary` schema with the additions
/// needed for GitHub install (repo, repo_path, commit_sha).
struct SkillEntry: Codable, Identifiable, Equatable, Sendable {
    /// UUID from the backend (nil for bundled-only fallback entries).
    let skillID: String?

    /// Lowercase-kebab-case folder name (e.g. "python-expert").
    /// Used as the primary key everywhere.
    let folder: String

    /// Human-readable display name (e.g. "Python Expert").
    let name: String

    /// Short description shown in the list.
    let description: String

    /// Link to the upstream source for this skill.
    let sourceURL: String

    /// GitHub "owner/repo" (e.g. "skilld-sh/skills"). Nil for bundled-only.
    let repo: String?

    /// Path inside the repo to the skill folder (e.g. "python-expert").
    let repoPath: String?

    /// Pinned commit SHA from the backend. Nil for bundled-only.
    let commitSHA: String?

    // Identifiable conformance — folder name is stable and unique.
    var id: String { folder }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case folder, name, description
        case skillID = "skill_id"
        case sourceURL = "source_url"
        case repo
        case repoPath = "repo_path"
        case commitSHA = "commit_sha"
    }

    // MARK: Factory — from API response

    /// Build a SkillEntry from an APISkillSummary returned by the backend.
    static func from(api summary: APISkillSummary) -> SkillEntry {
        SkillEntry(
            skillID: summary.id,
            folder: summary.folderName,
            name: summary.name,
            description: summary.description ?? "",
            sourceURL: summary.sourceURL,
            repo: summary.repo,
            repoPath: summary.repoPath,
            commitSHA: summary.commitSHA
        )
    }
}
