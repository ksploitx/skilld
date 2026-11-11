// SkillStore.swift
// skilld — menubar app
//
// @Observable view-model: fetches the skill catalogue from the backend API,
// falls back to the bundled skills.json when offline, debounces search input,
// checks for updates, and drives install/remove/update actions.
//
// Types used here:
//   SkillSummary, SkillDetail, SkillSearchResponse — from SkillsAPIClient.swift
//   APIError                                       — from APIError.swift
//   GitHubDownloader                               — from GitHubDownloader.swift
//   SkillInstaller, SkillInstallerError            — from SkillInstaller.swift
//   APIConfig                                      — from APIConfig.swift

import SwiftUI
import Observation
import Combine

// MARK: - SkillStore

@Observable
@MainActor
final class SkillStore {

    // MARK: Catalogue & search

    /// All skills currently shown in the list (API result or offline fallback).
    var skills: [SkillSummary] = []

    /// Bound to the search text field.
    var searchText: String = ""

    /// True while an API request is in-flight.
    var isLoading: Bool = false

    /// True when the backend is unreachable and we're showing the bundled list.
    var isOffline: Bool = false

    /// Folder names of installed skills that have a newer commitSha on the API.
    var updatesAvailable: Set<String> = []

    // MARK: Operation state per skill

    enum SkillOpState {
        case installing, removing, updating
    }
    /// Keyed by folderName.
    var operationState: [String: SkillOpState] = [:]
    /// Keyed by folderName.
    var operationError: [String: String] = [:]

    // MARK: Dependencies

    let installer: SkillInstaller
    private let apiClient: SkillsAPIClient
    private let downloader: GitHubDownloader
    private let bundle: Bundle

    // Combine pipeline for debounced search
    private var searchCancellable: AnyCancellable?
    private var searchTextSubject = PassthroughSubject<String, Never>()

    // MARK: Init

    /// Production init — real API client, installer, and main bundle.
    convenience init() {
        self.init(
            installer: SkillInstaller(),
            apiClient: SkillsAPIClient(),
            downloader: GitHubDownloader(),
            bundle: .main
        )
    }

    /// Testable init — inject all dependencies.
    init(
        installer: SkillInstaller,
        apiClient: SkillsAPIClient,
        downloader: GitHubDownloader,
        bundle: Bundle
    ) {
        self.installer = installer
        self.apiClient = apiClient
        self.downloader = downloader
        self.bundle = bundle
        setupDebounce()
    }

    // MARK: - Catalogue

    /// Call on popover open: load catalogue and check for updates.
    func refresh() {
        Task {
            await loadCatalogue(query: "")
            await checkForUpdates()
        }
    }

    // MARK: - Search

    /// Called whenever the search text field changes.
    /// Feeds the Combine debounce pipeline.
    func onSearchTextChanged(_ newValue: String) {
        searchTextSubject.send(newValue)
    }

    private func setupDebounce() {
        // 300 ms debounce — keeps API traffic low while typing.
        searchCancellable = searchTextSubject
            .debounce(for: .milliseconds(APIConfig.searchDebounceMsec), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                Task { @MainActor in
                    await self.loadCatalogue(query: text)
                }
            }
    }

    // MARK: - Filtered skills (offline mode only)

    /// Local filter applied only in offline mode (the API handles filtering when online).
    var filteredSkills: [SkillSummary] {
        guard isOffline, !searchText.isEmpty else { return skills }
        let q = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) ?? false) ||
            $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: - Install state helpers

    func isInstalled(_ skill: SkillSummary) -> Bool {
        (try? installer.loadManifest())?[skill.folderName] != nil
    }

    func hasUpdate(_ skill: SkillSummary) -> Bool {
        updatesAvailable.contains(skill.folderName)
    }

    // MARK: - Actions

    func install(_ skill: SkillSummary) {
        guard operationState[skill.folderName] == nil else { return }
        operationState[skill.folderName] = .installing
        operationError.removeValue(forKey: skill.folderName)

        Task {
            do {
                if skill.source == "bundled" || skill.repo.isEmpty {
                    try installFromBundle(skill)
                } else {
                    let skillDir = try await downloader.download(skill: skill)
                    // downloader returns the skill subdirectory; its grandparent is the temp root.
                    let tempRoot = skillDir.deletingLastPathComponent()
                        .deletingLastPathComponent()
                    defer { try? FileManager.default.removeItem(at: tempRoot) }
                    try installer.installFromDirectory(skill: skill, sourceDir: skillDir)
                }
                operationState.removeValue(forKey: skill.folderName)
            } catch {
                operationState.removeValue(forKey: skill.folderName)
                operationError[skill.folderName] = error.localizedDescription
            }
        }
    }

    func remove(_ skill: SkillSummary) {
        guard operationState[skill.folderName] == nil else { return }
        operationState[skill.folderName] = .removing
        operationError.removeValue(forKey: skill.folderName)

        Task {
            do {
                try installer.removeByFolder(skill.folderName)
                updatesAvailable.remove(skill.folderName)
                operationState.removeValue(forKey: skill.folderName)
            } catch {
                operationState.removeValue(forKey: skill.folderName)
                operationError[skill.folderName] = error.localizedDescription
            }
        }
    }

    func update(_ skill: SkillSummary) {
        guard operationState[skill.folderName] == nil else { return }
        operationState[skill.folderName] = .updating
        operationError.removeValue(forKey: skill.folderName)

        Task {
            do {
                if skill.repo.isEmpty {
                    try installFromBundle(skill)
                } else {
                    let skillDir = try await downloader.download(skill: skill)
                    let tempRoot = skillDir.deletingLastPathComponent()
                        .deletingLastPathComponent()
                    defer { try? FileManager.default.removeItem(at: tempRoot) }
                    try installer.installFromDirectory(skill: skill, sourceDir: skillDir)
                }
                updatesAvailable.remove(skill.folderName)
                operationState.removeValue(forKey: skill.folderName)
            } catch {
                operationState.removeValue(forKey: skill.folderName)
                operationError[skill.folderName] = error.localizedDescription
            }
        }
    }

    func clearError(for skill: SkillSummary) {
        operationError.removeValue(forKey: skill.folderName)
    }

    // MARK: - Private: Catalogue loading

    private func loadCatalogue(query: String) async {
        isLoading = true
        do {
            let response = try await apiClient.search(query: query)
            skills = response.results
            isOffline = false
        } catch APIError.offline, APIError.timeout {
            // Fall back to bundled list; local filter applied in filteredSkills.
            if !isOffline {
                loadBundledSkills()
                isOffline = true
            }
        } catch {
            // Server or decode error — keep whatever we have, don't wipe the list.
        }
        isLoading = false
    }

    private func loadBundledSkills() {
        guard let url = bundle.url(forResource: "skills", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }

        // Bundled skills.json uses SkillSummary-shaped JSON (snake_case keys).
        // The decoder in SkillsAPIClient uses convertFromSnakeCase, so mirror that here.
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        dec.dateDecodingStrategy = .formatted(formatter)

        if let summaries = try? dec.decode([SkillSummary].self, from: data) {
            skills = summaries
        }
        // If decode fails, leave skills unchanged (may still have API results).
    }

    // MARK: - Private: Update checking

    private func checkForUpdates() async {
        guard let manifest = try? installer.loadManifest(), !manifest.isEmpty else { return }
        let installedFolders = Set(manifest.keys)
        let manifestShas = Dictionary(uniqueKeysWithValues: manifest.map { ($0.key, $0.value.commitSha) })
        let oldestDate = manifest.values.map(\.installedAt).min() ?? .distantPast

        do {
            let updated = try await apiClient.updatedSince(timestamp: oldestDate)
            var newUpdates = updatesAvailable
            for skill in updated {
                guard installedFolders.contains(skill.folderName) else { continue }
                let stored = manifestShas[skill.folderName] ?? ""
                if !stored.isEmpty, stored != skill.commitSha {
                    newUpdates.insert(skill.folderName)
                }
            }
            updatesAvailable = newUpdates
        } catch {
            // Update check is best-effort; don't surface errors for it.
        }
    }

    // MARK: - Private: Bundle install

    private func installFromBundle(_ skill: SkillSummary) throws {
        guard let sourceFolder = bundle.url(
            forResource: skill.folderName,
            withExtension: nil,
            subdirectory: "skills"
        ) else {
            throw SkillInstallerError.sourceNotFound(
                URL(fileURLWithPath: "bundle://skills/\(skill.folderName)")
            )
        }
        try installer.installFromDirectory(skill: skill, sourceDir: sourceFolder)
    }
}
