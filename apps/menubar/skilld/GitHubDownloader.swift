// GitHubDownloader.swift
// skilld — menubar app
//
// Downloads a skill folder from GitHub at a pinned commit using the
// codeload tarball API, extracts the skill's subdirectory, validates it,
// then moves it into place atomically.
//
// Security rules enforced before any file touches ~/.claude/skills/:
//   • Only fetches from: github.com, api.github.com, codeload.github.com
//   • Rejects file paths containing ".." or starting with "/"
//   • Rejects symlinks
//   • Rejects archives > 5 MB extracted / > 100 files
//   • SKILL.md must exist in the extracted subtree
//   • Never leaves a partial folder behind on failure

import Foundation

// MARK: - Errors

enum GitHubDownloaderError: Error, LocalizedError {
    case disallowedHost(String)
    case rateLimited(retryAfterSeconds: Int?)
    case networkError(String)
    case extractionFailed(String)
    case skillMdMissing
    case pathTraversal(String)
    case symlinkDetected(String)
    case tooLarge(bytesFound: Int)
    case tooManyFiles(countFound: Int)
    case noSkillDirectory

    var errorDescription: String? {
        switch self {
        case .disallowedHost(let h):
            return "Security: skill content must come from github.com (got \(h))"
        case .rateLimited(let seconds):
            if let s = seconds {
                return "GitHub rate limit reached. Try again in \(s / 60 + 1) minutes."
            }
            return "GitHub rate limit reached. Try again later."
        case .networkError(let detail):
            return "Download failed: \(detail)"
        case .extractionFailed(let detail):
            return "Failed to extract skill archive: \(detail)"
        case .skillMdMissing:
            return "Invalid skill: SKILL.md not found in the downloaded folder."
        case .pathTraversal(let path):
            return "Security: rejected path '\(path)' — path traversal detected."
        case .symlinkDetected(let path):
            return "Security: rejected symlink at '\(path)'."
        case .tooLarge(let bytes):
            let mb = String(format: "%.1f", Double(bytes) / 1_048_576)
            return "Skill is too large (\(mb) MB). Limit is 5 MB."
        case .tooManyFiles(let count):
            return "Skill has too many files (\(count)). Limit is \(APIConfig.maxSkillFileCount)."
        case .noSkillDirectory:
            return "Skill directory not found inside the downloaded archive."
        }
    }
}

// MARK: - GitHubDownloader

/// Downloads, validates, and atomically installs a skill from GitHub.
///
/// Usage:
/// ```swift
/// let tempDir = try await downloader.download(skill: summary)
/// // tempDir now contains the validated skill folder.
/// // Pass it to SkillInstaller.installFromDirectory(_:sourceDir:).
/// ```
final class GitHubDownloader {

    // MARK: Properties

    private let session: URLSession

    // MARK: Init

    /// Production init.
    convenience init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.requestTimeout
        config.timeoutIntervalForResource = 120 // allow up to 2 min for large repos
        self.init(session: URLSession(configuration: config))
    }

    /// Testable init — inject a custom URLSession.
    init(session: URLSession) {
        self.session = session
    }

    // MARK: - Public API

    /// Download the skill at the given commit, extract it, validate it,
    /// and return a temporary directory URL containing the validated skill folder.
    ///
    /// The caller is responsible for passing the returned URL to
    /// `SkillInstaller.installFromDirectory(_:sourceDir:)` and then
    /// cleaning up the temp directory.
    ///
    /// - Parameters:
    ///   - skill: The API summary containing repo, repoPath, and commitSha.
    /// - Returns: URL of a temp directory holding the validated skill subtree.
    /// - Throws: `GitHubDownloaderError` for any security or network failure.
    func download(skill: SkillSummary) async throws -> URL {
        guard !skill.repo.isEmpty, !skill.commitSha.isEmpty else {
            throw GitHubDownloaderError.networkError("Skill is missing repo or commitSha — cannot download from GitHub.")
        }

        // Build codeload tarball URL: https://codeload.github.com/{owner}/{repo}/tar.gz/{sha}
        let tarballURL = try buildTarballURL(repo: skill.repo, commitSha: skill.commitSha)

        // Validate host
        try validateHost(tarballURL)

        // Download to a temp file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("skilld-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            // On any failure path the caller didn't reach installFromDirectory,
            // so clean up. On success the caller owns the directory.
        }

        let tarFile = tempDir.appendingPathComponent("archive.tar.gz")

        do {
            try await downloadFile(from: tarballURL, to: tarFile)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        // Extract
        let extractDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        do {
            try extractTarGz(at: tarFile, into: extractDir)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        // Locate the skill subtree inside the extracted archive.
        // GitHub tarballs extract into a top-level folder named "<repo>-<sha>/"
        // The skill is at: <top>/<repoPath>/
        let skillSubdir: URL
        do {
            skillSubdir = try findSkillSubdirectory(in: extractDir, repoPath: skill.repoPath)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        // Validate contents
        do {
            try validateSkillDirectory(skillSubdir)
        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            throw error
        }

        return skillSubdir
    }

    // MARK: - Private: URL building

    private func buildTarballURL(repo: String, commitSha: String) throws -> URL {
        // repo is "owner/repo" — validate it has exactly one "/"
        let parts = repo.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else {
            throw GitHubDownloaderError.networkError("Invalid repo format '\(repo)' — expected 'owner/repo'")
        }
        let urlString = "https://codeload.github.com/\(repo)/tar.gz/\(commitSha)"
        guard let url = URL(string: urlString) else {
            throw GitHubDownloaderError.networkError("Could not build tarball URL for \(repo)@\(commitSha)")
        }
        return url
    }

    private func validateHost(_ url: URL) throws {
        guard let host = url.host, APIConfig.allowedGitHubHosts.contains(host) else {
            throw GitHubDownloaderError.disallowedHost(url.host ?? "(no host)")
        }
    }

    // MARK: - Private: Downloading

    private func downloadFile(from url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue("skilld-menubar/1.0", forHTTPHeaderField: "User-Agent")

        let (downloadURL, response): (URL, URLResponse)
        do {
            (downloadURL, response) = try await session.download(for: request)
        } catch let urlError as URLError {
            throw GitHubDownloaderError.networkError(urlError.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubDownloaderError.networkError("Non-HTTP response")
        }

        if http.statusCode == 403 || http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
                ?? http.value(forHTTPHeaderField: "X-RateLimit-Reset")
                    .flatMap(TimeInterval.init)
                    .map { max(0, Int($0 - Date().timeIntervalSince1970)) }
            throw GitHubDownloaderError.rateLimited(retryAfterSeconds: retryAfter)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw GitHubDownloaderError.networkError("HTTP \(http.statusCode) from GitHub")
        }

        // Validate redirect chain: every hop must stay on allowed hosts
        if let finalURL = http.url {
            try validateHost(finalURL)
        }

        try FileManager.default.moveItem(at: downloadURL, to: destination)
    }

    // MARK: - Private: Extraction

    /// Shell out to /usr/bin/tar (ships with macOS) to extract the archive.
    private func extractTarGz(at archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "xzf", archive.path,
            "-C", directory.path,
            "--no-same-owner",   // don't try to restore ownership (would need root)
            "--no-same-permissions",
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw GitHubDownloaderError.extractionFailed("tar exited \(process.terminationStatus): \(errMsg)")
        }
    }

    // MARK: - Private: Locating the skill subtree

    /// Finds the skill's subdirectory within the extracted archive.
    ///
    /// GitHub tarballs produce a top-level folder like `{repo}-{sha}/`.
    /// The skill lives at `{top}/{repoPath}/`.
    private func findSkillSubdirectory(in extractDir: URL, repoPath: String) throws -> URL {
        let fm = FileManager.default
        let topLevelEntries = try fm.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        guard let topLevel = topLevelEntries.first(where: {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) else {
            throw GitHubDownloaderError.extractionFailed("Archive produced no top-level directory")
        }

        let skillDir = repoPath.isEmpty ? topLevel : topLevel.appendingPathComponent(repoPath, isDirectory: true)

        guard fm.fileExists(atPath: skillDir.path) else {
            throw GitHubDownloaderError.noSkillDirectory
        }

        return skillDir
    }

    // MARK: - Private: Validation

    /// Validate the extracted skill directory before it touches ~/.claude/skills/.
    private func validateSkillDirectory(_ dir: URL) throws {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw GitHubDownloaderError.extractionFailed("Cannot enumerate skill directory")
        }

        var foundSkillMd = false
        var totalBytes = 0
        var fileCount = 0

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")

            // 1. No path traversal
            guard !relativePath.contains("..") else {
                throw GitHubDownloaderError.pathTraversal(relativePath)
            }
            guard !relativePath.hasPrefix("/") else {
                throw GitHubDownloaderError.pathTraversal(relativePath)
            }

            // 2. No symlinks
            let resourceValues = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            if resourceValues.isSymbolicLink == true {
                throw GitHubDownloaderError.symlinkDetected(relativePath)
            }

            guard resourceValues.isRegularFile == true else { continue }

            // 3. File count cap
            fileCount += 1
            if fileCount > APIConfig.maxSkillFileCount {
                throw GitHubDownloaderError.tooManyFiles(countFound: fileCount)
            }

            // 4. Size cap
            let fileSize = resourceValues.fileSize ?? 0
            totalBytes += fileSize
            if totalBytes > APIConfig.maxSkillSizeBytes {
                throw GitHubDownloaderError.tooLarge(bytesFound: totalBytes)
            }

            // 5. SKILL.md detection
            if relativePath == "SKILL.md" {
                foundSkillMd = true
            }
        }

        // 6. SKILL.md is required
        if !foundSkillMd {
            throw GitHubDownloaderError.skillMdMissing
        }
    }
}
