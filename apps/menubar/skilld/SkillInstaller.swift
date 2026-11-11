// SkillInstaller.swift
// skilld — menubar app
//
// Pure Swift class: no UI imports, no SwiftUI, no AppKit, no networking.
// All filesystem mutations go through this one file so it can be fully
// covered by XCTest using a temp directory.
//
// Responsibilities:
//   - Validate folder names
//   - Install (copy) a skill folder from a local source directory
//   - Remove a skill folder (only if tracked in the manifest)
//   - Track installed state in ~/.claude/skilld-manifest.json
//   - Compute a deterministic SHA-256 content hash for a folder
//
// GitHub download is handled by GitHubDownloader.swift.
// API responses are modelled in SkillsAPIClient.swift (SkillSummary).

import Foundation
import CryptoKit

// MARK: - Constants

/// The user-level Claude Code skills directory.
/// Source: docs/CLAUDE_CODE_SKILLS.md §1 — "Personal (user-level, global)"
let claudeSkillsDirectory: URL = {
    FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/skills", directoryHint: .isDirectory)
}()

// MARK: - Errors

enum SkillInstallerError: Error, LocalizedError {
    case invalidFolderName(String)
    case reservedName(String)
    case pathTraversal(String)
    case sourceNotFound(URL)
    case alreadyExistsNotOwned(URL)
    case notInstalled(String)

    var errorDescription: String? {
        switch self {
        case .invalidFolderName(let n):
            return "'\(n)' is not a valid skill folder name. Use lowercase letters, digits, and hyphens only."
        case .reservedName(let n):
            return "'\(n)' is a reserved name used by Claude Code. Choose a different name."
        case .pathTraversal(let n):
            return "'\(n)' contains path traversal characters and was rejected."
        case .sourceNotFound(let url):
            return "Skill folder not found at \(url.path)."
        case .alreadyExistsNotOwned(let url):
            return "\(url.lastPathComponent) already exists in your skills directory but was not installed by skilld. Remove it manually first."
        case .notInstalled(let n):
            return "'\(n)' is not tracked in the skilld manifest."
        }
    }
}

// MARK: - Manifest types

struct ManifestEntry: Codable, Equatable {
    let folder: String
    let installedAt: Date
    /// SHA-256 hex digest of all file contents, sorted by relative path.
    /// Deterministic: same tree → same hash.
    let contentHash: String
    /// Pinned GitHub commit SHA at install time. Empty string for bundled skills.
    let commitSha: String
}

// MARK: - SkillInstaller

/// Manages installing and removing Claude Code skill folders.
///
/// All paths are injected so XCTest can redirect operations to a temp
/// directory instead of the real `~/.claude/skills/`.
final class SkillInstaller {

    // MARK: Paths

    /// Where skills are written on disk.
    let skillsDirectory: URL

    /// Where the local tracking manifest is stored.
    let manifestURL: URL

    // MARK: Init

    /// Production initialiser — uses `~/.claude/skills/` and
    /// `~/.claude/skilld-manifest.json`.
    convenience init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude", directoryHint: .isDirectory)
        self.init(
            skillsDirectory: base.appending(path: "skills", directoryHint: .isDirectory),
            manifestURL: base.appending(path: "skilld-manifest.json")
        )
    }

    /// Testable initialiser — callers supply custom paths.
    init(skillsDirectory: URL, manifestURL: URL) {
        self.skillsDirectory = skillsDirectory
        self.manifestURL = manifestURL
    }

    // MARK: - Public API: Install

    /// Copy `sourceFolder` into `skillsDirectory/<skill.folder>/`.
    /// Used for installing from the app bundle (offline fallback).
    func install(skill: SkillEntry, sourceFolder: URL) throws {
        try validateFolderName(skill.folder)
        try installCore(folderName: skill.folder, sourceDir: sourceFolder, commitSha: "")
    }

    /// Install a skill from a pre-validated directory (e.g. returned by GitHubDownloader).
    /// The source directory is COPIED (not moved) so the caller can clean up its temp dir.
    ///
    /// This is the preferred path for all online installs.
    func installFromDirectory(skill: SkillSummary, sourceDir: URL) throws {
        try validateFolderName(skill.folderName)
        try installCore(folderName: skill.folderName, sourceDir: sourceDir, commitSha: skill.commitSha)
    }

    // MARK: - Public API: Remove

    /// Delete the skill folder **only if** it was installed by skilld.
    func remove(skill: SkillEntry) throws {
        try removeByFolder(skill.folder)
    }

    /// Delete the skill folder by folder name — only if tracked in our manifest.
    /// Used by `SkillStore` when working with `SkillSummary`.
    func removeByFolder(_ folderName: String) throws {
        var manifest = try loadManifest()
        guard manifest[folderName] != nil else {
            throw SkillInstallerError.notInstalled(folderName)
        }

        let destination = skillsDirectory.appending(path: folderName, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        manifest.removeValue(forKey: folderName)
        try saveManifest(manifest)
    }

    // MARK: - Public API: Query

    /// True when the skill is tracked in the manifest (i.e. installed by us).
    func isInstalled(_ skill: SkillEntry) -> Bool {
        (try? loadManifest())?[skill.folder] != nil
    }

    /// True when the manifest's stored content hash differs from the given source folder's hash.
    /// Used for bundled-skill update detection. Returns `false` if the skill is not installed.
    func updateAvailable(skill: SkillEntry, sourceFolder: URL) -> Bool {
        guard let manifest = try? loadManifest(),
              let entry = manifest[skill.folder],
              let bundledHash = try? contentHash(of: sourceFolder) else {
            return false
        }
        return entry.contentHash != bundledHash
    }

    // MARK: - Manifest helpers (internal for testing)

    func loadManifest() throws -> [String: ManifestEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestURL.path) else { return [:] }
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: ManifestEntry].self, from: data)
    }

    private func saveManifest(_ manifest: [String: ManifestEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Validation

    /// Validates that `name` is a safe, lowercase-kebab-case skill folder name.
    /// Rules derived from docs/CLAUDE_CODE_SKILLS.md §5.
    func validateFolderName(_ name: String) throws {
        // Reject path traversal characters first (before charset check)
        guard !name.contains(".."), !name.contains("/"), !name.contains("\\") else {
            throw SkillInstallerError.pathTraversal(name)
        }

        // Must match [a-z0-9-]+ (lowercase-kebab-case), non-empty
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw SkillInstallerError.invalidFolderName(name)
        }

        // Reserved name — Claude Code uses this for synced skills
        if name.lowercased() == "synced" {
            throw SkillInstallerError.reservedName(name)
        }
    }

    // MARK: - Content hashing

    /// SHA-256 of all file contents in `folder`, sorted by relative path.
    /// Deterministic: same tree → same hash, regardless of filesystem order.
    func contentHash(of folder: URL) throws -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let resources = try url.resourceValues(forKeys: [.isRegularFileKey])
            if resources.isRegularFile == true {
                files.append(url)
            }
        }

        // Sort by path for determinism
        files.sort { $0.path < $1.path }

        var hasher = SHA256()
        for file in files {
            // Include relative path in hash so renames are detected
            let relativePath = file.path.replacingOccurrences(of: folder.path, with: "")
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: try Data(contentsOf: file))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private core install

    /// Shared implementation for all install paths.
    /// - Parameters:
    ///   - folderName: validated kebab-case folder name.
    ///   - sourceDir:  directory to copy from (must exist).
    ///   - commitSha:  pinned commit SHA, or "" for bundled skills.
    private func installCore(folderName: String, sourceDir: URL, commitSha: String) throws {
        let fm = FileManager.default
        let destination = skillsDirectory.appending(path: folderName, directoryHint: .isDirectory)

        // Ensure ~/.claude/skills/ exists (mkdir -p semantics)
        try fm.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)

        // If the destination already exists it must be ours
        if fm.fileExists(atPath: destination.path) {
            var manifest = try loadManifest()
            guard manifest[folderName] != nil else {
                throw SkillInstallerError.alreadyExistsNotOwned(destination)
            }
            // It's ours — remove the old copy before writing fresh
            try fm.removeItem(at: destination)
            manifest.removeValue(forKey: folderName)
            try saveManifest(manifest)
        }

        guard fm.fileExists(atPath: sourceDir.path) else {
            throw SkillInstallerError.sourceNotFound(sourceDir)
        }

        try fm.copyItem(at: sourceDir, to: destination)

        let hash = try contentHash(of: destination)
        var manifest = try loadManifest()
        manifest[folderName] = ManifestEntry(
            folder: folderName,
            installedAt: Date(),
            contentHash: hash,
            commitSha: commitSha
        )
        try saveManifest(manifest)
    }
}
