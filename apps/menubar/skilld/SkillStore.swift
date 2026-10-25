// SkillStore.swift
// skilld — menubar app
//
// @Observable view-model that bridges the catalogue (skills.json) and
// SkillInstaller into a SwiftUI-friendly surface.

import SwiftUI
import Observation

@Observable
@MainActor
final class SkillStore {

    // MARK: State

    var skills: [SkillEntry] = []
    var searchText: String = ""

    /// Per-skill operation state for button feedback.
    var operationState: [String: OperationState] = [:]

    /// Last error message to surface in the UI.
    var lastError: String?

    // MARK: Derived

    var filteredSkills: [SkillEntry] {
        guard !searchText.isEmpty else { return skills }
        let q = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q)
        }
    }

    // MARK: Dependencies

    private let installer: SkillInstaller
    private let bundle: Bundle

    // MARK: Init

    /// Production init — uses real home directory + main bundle.
    convenience init() {
        self.init(installer: SkillInstaller(), bundle: .main)
    }

    /// Testable init — inject a custom installer and bundle.
    init(installer: SkillInstaller, bundle: Bundle) {
        self.installer = installer
        self.bundle = bundle
        reload()
    }

    // MARK: Catalogue loading

    func reload() {
        guard let url = bundle.url(forResource: "skills", withExtension: "json") else {
            lastError = "skills.json not found in app bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            skills = try JSONDecoder().decode([SkillEntry].self, from: data)
        } catch {
            lastError = "Failed to load skill catalogue: \(error.localizedDescription)"
        }
    }

    // MARK: Status helpers

    func isInstalled(_ skill: SkillEntry) -> Bool {
        installer.isInstalled(skill)
    }

    func updateAvailable(_ skill: SkillEntry) -> Bool {
        guard let sourceFolder = bundleFolder(for: skill) else { return false }
        return installer.updateAvailable(skill: skill, sourceFolder: sourceFolder)
    }

    // MARK: Actions

    func install(_ skill: SkillEntry) {
        guard let sourceFolder = bundleFolder(for: skill) else {
            lastError = "Bundle folder missing for \(skill.folder)."
            return
        }
        operationState[skill.id] = .inProgress
        do {
            try installer.install(skill: skill, sourceFolder: sourceFolder)
            operationState[skill.id] = .success
        } catch {
            operationState[skill.id] = .failure
            lastError = error.localizedDescription
        }
    }

    func remove(_ skill: SkillEntry) {
        operationState[skill.id] = .inProgress
        do {
            try installer.remove(skill: skill)
            operationState[skill.id] = .success
        } catch {
            operationState[skill.id] = .failure
            lastError = error.localizedDescription
        }
    }

    func update(_ skill: SkillEntry) {
        // Update = reinstall from bundle (installer handles the overwrite)
        install(skill)
    }

    // MARK: Private

    private func bundleFolder(for skill: SkillEntry) -> URL? {
        bundle.url(forResource: skill.folder, withExtension: nil,
                   subdirectory: "skills")
    }
}

// MARK: - Supporting types

enum OperationState {
    case inProgress, success, failure
}
