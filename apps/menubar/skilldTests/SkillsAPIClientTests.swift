// SkillsAPIClientTests.swift
// skilldTests
//
// XCTest suite for SkillsAPIClient — all tests use MockURLProtocol,
// no real network is touched.

import XCTest
@testable import skilld

final class SkillsAPIClientTests: XCTestCase {

    private var client: SkillsAPIClient!
    private var baseURL: URL!

    override func setUp() {
        super.setUp()
        baseURL = URL(string: "http://localhost:8000")!
        client = SkillsAPIClient(session: MockURLProtocol.makeSession(), baseURL: baseURL)
        MockURLProtocol.requestHandler = nil
    }

    // MARK: - search

    func test_search_decodesSuccessResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(json: Self.sampleSearchResponseJSON)
        }
        let response = try await client.search(query: "python")
        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(response.results.count, 1)
        let skill = try XCTUnwrap(response.results.first)
        XCTAssertEqual(skill.name, "Python Expert")
        XCTAssertEqual(skill.folderName, "python-expert")
        XCTAssertEqual(skill.repo, "skilld-sh/skills")
        XCTAssertEqual(skill.commitSha, "abc123def456")
        XCTAssertFalse(skill.sourceURL.isEmpty)
    }

    func test_search_emptyQueryReturnsAll() async throws {
        MockURLProtocol.requestHandler = { request in
            // Verify the query param is present (even if empty)
            let url = try XCTUnwrap(request.url)
            XCTAssertTrue(url.absoluteString.contains("query="))
            return MockURLProtocol.respond(json: Self.emptySearchResponseJSON)
        }
        let response = try await client.search()
        XCTAssertEqual(response.results.count, 0)
        XCTAssertEqual(response.total, 0)
    }

    func test_search_serverError_throwsAPIError() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(statusCode: 500, body: "Internal Server Error")
        }
        do {
            _ = try await client.search()
            XCTFail("Expected APIError.serverError to be thrown")
        } catch APIError.serverError(let code, _) {
            XCTAssertEqual(code, 500)
        }
    }

    func test_search_notFound_throwsAPIError() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(statusCode: 404, body: "Not found")
        }
        do {
            _ = try await client.search()
            XCTFail("Expected APIError.serverError to be thrown")
        } catch APIError.serverError(let code, _) {
            XCTAssertEqual(code, 404)
        }
    }

    func test_search_timeout_throwsAPIError() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }
        do {
            _ = try await client.search()
            XCTFail("Expected APIError.timeout")
        } catch APIError.timeout {
            // expected
        }
    }

    func test_search_offline_throwsAPIError() async throws {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        do {
            _ = try await client.search()
            XCTFail("Expected APIError.offline")
        } catch APIError.offline {
            // expected
        }
    }

    func test_search_invalidJSON_throwsDecodingError() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(json: Data("not json".utf8))
        }
        do {
            _ = try await client.search()
            XCTFail("Expected APIError.decodingError")
        } catch APIError.decodingError {
            // expected
        }
    }

    func test_search_malformedJSON_throwsDecodingError() async throws {
        // Valid JSON but wrong shape
        let badShape = Data(#"{"wrong_field": true}"#.utf8)
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(json: badShape)
        }
        do {
            _ = try await client.search()
            XCTFail("Expected APIError.decodingError")
        } catch APIError.decodingError {
            // expected
        }
    }

    // MARK: - get(id:)

    func test_get_decodesSuccessResponse() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(json: Self.sampleSkillDetailJSON)
        }
        let detail = try await client.get(id: "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(detail.folderName, "python-expert")
        XCTAssertFalse(detail.skillMd.isEmpty)
    }

    // MARK: - updatedSince

    func test_updatedSince_decodesArray() async throws {
        MockURLProtocol.requestHandler = { request in
            // Verify ts query param is present
            let url = try XCTUnwrap(request.url)
            XCTAssertTrue(url.absoluteString.contains("ts="))
            return MockURLProtocol.respond(json: Self.sampleUpdatedSinceJSON)
        }
        let results = try await client.updatedSince(timestamp: .distantPast)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].folderName, "python-expert")
    }

    func test_updatedSince_emptyArray_succeeds() async throws {
        MockURLProtocol.requestHandler = { _ in
            MockURLProtocol.respond(json: Data("[]".utf8))
        }
        let results = try await client.updatedSince(timestamp: Date())
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Sample JSON fixtures

    private static let sampleSearchResponseJSON = Data("""
    {
        "results": [
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "name": "Python Expert",
                "folder_name": "python-expert",
                "description": "Expert Python coding assistant.",
                "tags": ["python", "typing"],
                "source": "github",
                "source_url": "https://github.com/skilld-sh/skills/tree/main/python-expert",
                "repo": "skilld-sh/skills",
                "repo_path": "python-expert",
                "commit_sha": "abc123def456",
                "updated_at": "2026-01-01T00:00:00Z"
            }
        ],
        "total": 1,
        "limit": 20,
        "offset": 0
    }
    """.utf8)

    private static let emptySearchResponseJSON = Data("""
    {"results": [], "total": 0, "limit": 20, "offset": 0}
    """.utf8)

    private static let sampleSkillDetailJSON = Data("""
    {
        "id": "00000000-0000-0000-0000-000000000001",
        "name": "Python Expert",
        "folder_name": "python-expert",
        "description": "Expert Python.",
        "tags": ["python"],
        "source": "github",
        "source_url": "https://github.com/skilld-sh/skills/tree/main/python-expert",
        "repo": "skilld-sh/skills",
        "repo_path": "python-expert",
        "commit_sha": "abc123def456",
        "skill_md": "---\\ndescription: Expert Python.\\n---\\nContent here.",
        "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z"
    }
    """.utf8)

    private static let sampleUpdatedSinceJSON = Data("""
    [
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Python Expert",
            "folder_name": "python-expert",
            "description": "Expert Python.",
            "tags": ["python"],
            "source": "github",
            "source_url": "https://github.com/skilld-sh/skills/tree/main/python-expert",
            "repo": "skilld-sh/skills",
            "repo_path": "python-expert",
            "commit_sha": "newsha999",
            "updated_at": "2026-06-01T00:00:00Z"
        }
    ]
    """.utf8)
}

