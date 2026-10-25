// SkillInstallerTests.swift
// skilldTests
//
// XCTest suite for SkillInstaller.
// All operations use a temporary directory — the real ~/.claude/skills/
// is never touched.

import XCTest
@testable import skilld

final class SkillInstallerTests: XCTestCase {

    // MARK: Helpers

    private var tempDir: URL!
    private var skillsDir: URL!
    private var manifestURL: URL!
    private var installer: SkillInstaller!

    /// A sample source skill folder in our temp space.
    private var sampleSourceDir: URL!
    private let sampleSkill = SkillEntry(
        folder: "test-skill",
        name: "Test Skill",
        description: "A skill used only in tests.",
        sourceURL: "https://example.com"
    )

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "skilld-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        skillsDir = tempDir.appending(path: "skills", directoryHint: .isDirectory)
        manifestURL = tempDir.appending(path: "skilld-manifest.json")
        installer = SkillInstaller(skillsDirectory: skillsDir, manifestURL: manifestURL)

        // Build a minimal source skill folder in temp space
        sampleSourceDir = tempDir.appending(path: "source/test-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sampleSourceDir, withIntermediateDirectories: true)
        try "---\ndescription: Test.\n---\nHello\n"
            .write(to: sampleSourceDir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - install

    func test_install_validSkill_copiesFolder() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)

        let destination = skillsDir.appending(path: sampleSkill.folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let skillMD = destination.appending(path: "SKILL.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillMD.path))
    }

    func test_install_createsSkillsDirIfMissing() throws {
        // skillsDir does not exist yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: skillsDir.path))

        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)

        XCTAssertTrue(FileManager.default.fileExists(atPath: skillsDir.path))
    }

    func test_install_writesManifestEntry() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)

        let manifest = try installer.loadManifest()
        XCTAssertNotNil(manifest[sampleSkill.folder])
    }

    func test_install_manifestEntryHasNonEmptyHash() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)

        let entry = try XCTUnwrap(installer.loadManifest()[sampleSkill.folder])
        XCTAssertFalse(entry.contentHash.isEmpty)
    }

    // MARK: - remove

    func test_remove_deletesFolder() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)
        try installer.remove(skill: sampleSkill)

        let destination = skillsDir.appending(path: sampleSkill.folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func test_remove_removesManifestEntry() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)
        try installer.remove(skill: sampleSkill)

        let manifest = try installer.loadManifest()
        XCTAssertNil(manifest[sampleSkill.folder])
    }

    func test_remove_notInstalled_throws() throws {
        XCTAssertThrowsError(try installer.remove(skill: sampleSkill)) { error in
            guard case SkillInstallerError.notInstalled = error else {
                return XCTFail("Expected notInstalled, got \(error)")
            }
        }
    }

    // MARK: - reinstall

    func test_reinstall_afterRemove_succeeds() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)
        try installer.remove(skill: sampleSkill)
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)

        XCTAssertTrue(installer.isInstalled(sampleSkill))
    }

    // MARK: - invalid names

    func test_validateFolderName_valid_passes() throws {
        XCTAssertNoThrow(try installer.validateFolderName("my-skill"))
        XCTAssertNoThrow(try installer.validateFolderName("python-expert"))
        XCTAssertNoThrow(try installer.validateFolderName("skill123"))
    }

    func test_validateFolderName_uppercase_fails() throws {
        XCTAssertThrowsError(try installer.validateFolderName("MySkill")) { error in
            guard case SkillInstallerError.invalidFolderName = error else {
                return XCTFail("Expected invalidFolderName")
            }
        }
    }

    func test_validateFolderName_withSpace_fails() throws {
        XCTAssertThrowsError(try installer.validateFolderName("my skill")) { error in
            guard case SkillInstallerError.invalidFolderName = error else {
                return XCTFail("Expected invalidFolderName")
            }
        }
    }

    func test_validateFolderName_empty_fails() throws {
        XCTAssertThrowsError(try installer.validateFolderName("")) { error in
            guard case SkillInstallerError.invalidFolderName = error else {
                return XCTFail("Expected invalidFolderName")
            }
        }
    }

    func test_validateFolderName_synced_fails() throws {
        XCTAssertThrowsError(try installer.validateFolderName("synced")) { error in
            guard case SkillInstallerError.reservedName = error else {
                return XCTFail("Expected reservedName")
            }
        }
    }

    func test_validateFolderName_dotDot_fails() throws {
        XCTAssertThrowsError(try installer.validateFolderName("../etc")) { error in
            guard case SkillInstallerError.pathTraversal = error else {
                return XCTFail("Expected pathTraversal")
            }
        }
    }

    func test_validateFolderName_forwardSlash_fails() throws {
        XCTAssertThrowsError(try installer.validateFolderName("a/b")) { error in
            guard case SkillInstallerError.pathTraversal = error else {
                return XCTFail("Expected pathTraversal")
            }
        }
    }

    // MARK: - existing folder not in manifest

    func test_install_existingFolderNotOwned_throws() throws {
        // Create a folder at the destination without installing through the installer
        let orphanDir = skillsDir.appending(path: sampleSkill.folder)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        // Don't add a manifest entry — simulate a folder we didn't install

        XCTAssertThrowsError(try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)) { error in
            guard case SkillInstallerError.alreadyExistsNotOwned = error else {
                return XCTFail("Expected alreadyExistsNotOwned, got \(error)")
            }
        }
    }

    // MARK: - hash change detection

    func test_updateAvailable_sameContent_returnsFalse() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)
        // Source folder hasn't changed
        XCTAssertFalse(installer.updateAvailable(skill: sampleSkill, sourceFolder: sampleSourceDir))
    }

    func test_updateAvailable_changedContent_returnsTrue() throws {
        try installer.install(skill: sampleSkill, sourceFolder: sampleSourceDir)

        // Modify the bundled source to simulate a new version
        let skillMD = sampleSourceDir.appending(path: "SKILL.md")
        try "---\ndescription: Updated.\n---\nNew content\n"
            .write(to: skillMD, atomically: true, encoding: .utf8)

        XCTAssertTrue(installer.updateAvailable(skill: sampleSkill, sourceFolder: sampleSourceDir))
    }

    func test_updateAvailable_notInstalled_returnsFalse() throws {
        XCTAssertFalse(installer.updateAvailable(skill: sampleSkill, sourceFolder: sampleSourceDir))
    }
}
