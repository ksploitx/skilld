// SkillInstaller.swift
// skilld — menubar app
//
// Pure Swift class: no UI imports, no SwiftUI, no AppKit.
// All filesystem mutations go through this one file so it can be
// fully covered by XCTest using a temp directory.

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
            return "Bundled skill folder not found at \(url.path)."
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
    let contentHash: String  // SHA-256 hex of all file contents, sorted by relative path
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

    // MARK: Public API

    /// Copy `sourceFolder` into `skillsDirectory/<skill.folder>/`.
    /// - `sourceFolder`: the on-disk folder to copy (from the app bundle).
    func install(skill: SkillEntry, sourceFolder: URL) throws {
        try validateFolderName(skill.folder)

        let destination = skillsDirectory.appending(path: skill.folder, directoryHint: .isDirectory)
        let fm = FileManager.default

        // Ensure ~/.claude/skills/ exists (mkdir -p semantics)
        try fm.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)

        // If the destination already exists it must be ours
        if fm.fileExists(atPath: destination.path) {
            var manifest = try loadManifest()
            guard manifest[skill.folder] != nil else {
                throw SkillInstallerError.alreadyExistsNotOwned(destination)
            }
            // It's ours — remove the old copy before writing fresh
            try fm.removeItem(at: destination)
            manifest.removeValue(forKey: skill.folder)
            try saveManifest(manifest)
        }

        guard fm.fileExists(atPath: sourceFolder.path) else {
            throw SkillInstallerError.sourceNotFound(sourceFolder)
        }

        try fm.copyItem(at: sourceFolder, to: destination)

        let hash = try contentHash(of: destination)
        var manifest = try loadManifest()
        manifest[skill.folder] = ManifestEntry(
            folder: skill.folder,
            installedAt: Date(),
            contentHash: hash
        )
        try saveManifest(manifest)
    }

    /// Delete the skill folder **only if** it was installed by skilld.
    func remove(skill: SkillEntry) throws {
        var manifest = try loadManifest()
        guard manifest[skill.folder] != nil else {
            throw SkillInstallerError.notInstalled(skill.folder)
        }

        let destination = skillsDirectory.appending(path: skill.folder, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        manifest.removeValue(forKey: skill.folder)
        try saveManifest(manifest)
    }

    /// True when the skill's folder exists in the manifest (i.e. installed by us).
    func isInstalled(_ skill: SkillEntry) -> Bool {
        (try? loadManifest())?[skill.folder] != nil
    }

    /// True when the manifest's stored hash differs from the current bundled hash.
    /// Returns `false` if the skill is not installed.
    func updateAvailable(skill: SkillEntry, sourceFolder: URL) -> Bool {
        guard let manifest = try? loadManifest(),
              let entry = manifest[skill.folder],
              let bundledHash = try? contentHash(of: sourceFolder) else {
            return false
        }
        return entry.contentHash != bundledHash
    }

    // MARK: Manifest helpers

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

    // MARK: Validation

    /// Validates that `name` is a safe, lowercase-kebab-case skill folder name.
    /// Rules derived from docs/CLAUDE_CODE_SKILLS.md §5.
    func validateFolderName(_ name: String) throws {
        // Reject path traversal characters
        guard !name.contains(".."), !name.contains("/"), !name.contains("\\") else {
            throw SkillInstallerError.pathTraversal(name)
        }

        // Must match [a-z0-9-]+ (lowercase-kebab-case)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !name.isEmpty, name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw SkillInstallerError.invalidFolderName(name)
        }

        // Reserved name — Claude Code uses this for synced skills
        if name.lowercased() == "synced" {
            throw SkillInstallerError.reservedName(name)
        }
    }

    // MARK: Content hashing

    /// SHA-256 of all file contents in `folder`, with files sorted by relative path.
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
}
