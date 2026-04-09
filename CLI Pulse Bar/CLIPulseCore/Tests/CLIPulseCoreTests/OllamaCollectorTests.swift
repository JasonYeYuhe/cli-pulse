#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class OllamaCollectorTests: XCTestCase {

    // MARK: - Tags parsing

    func testParseTagsNormal() throws {
        let json = """
        {
            "models": [
                {"name": "llama3:latest", "size": 4661224416},
                {"name": "codellama:7b", "size": 3825819519},
                {"name": "mistral:latest", "size": 4109865159}
            ]
        }
        """.data(using: .utf8)!

        let models = try OllamaCollector.parseTags(json)
        XCTAssertEqual(models.count, 3)
        XCTAssertEqual(models[0].name, "llama3:latest")
        XCTAssertEqual(models[0].size, 4661224416)
        XCTAssertEqual(models[1].name, "codellama:7b")
    }

    func testParseTagsEmpty() throws {
        let json = """
        { "models": [] }
        """.data(using: .utf8)!

        let models = try OllamaCollector.parseTags(json)
        XCTAssertTrue(models.isEmpty)
    }

    func testParseTagsNoModelsKey() {
        let json = "{}".data(using: .utf8)!
        XCTAssertThrowsError(try OllamaCollector.parseTags(json))
    }

    func testParseTagsInvalidJSON() {
        let bad = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try OllamaCollector.parseTags(bad))
    }

    // MARK: - Running models parsing

    func testParseRunningNormal() throws {
        let json = """
        {
            "models": [
                {"name": "llama3:latest", "size": 4661224416},
                {"name": "codellama:7b", "size": 3825819519}
            ]
        }
        """.data(using: .utf8)!

        let running = try OllamaCollector.parseRunning(json)
        XCTAssertEqual(running, ["llama3:latest", "codellama:7b"])
    }

    func testParseRunningEmpty() throws {
        let json = """
        { "models": [] }
        """.data(using: .utf8)!

        let running = try OllamaCollector.parseRunning(json)
        XCTAssertTrue(running.isEmpty)
    }

    func testParseRunningMissingKey() throws {
        let json = "{}".data(using: .utf8)!
        let running = try OllamaCollector.parseRunning(json)
        XCTAssertTrue(running.isEmpty)
    }

    // MARK: - Availability

    func testCollectorKind() {
        XCTAssertEqual(OllamaCollector().kind, .ollama)
    }

    func testAvailabilityDependsOnServer() {
        // isAvailable now does a TCP connect check to localhost:11434.
        // In CI / test environments Ollama is typically not running,
        // so we just verify the method returns without crashing.
        let collector = OllamaCollector()
        let config = ProviderConfig(kind: .ollama)
        _ = collector.isAvailable(config: config)
    }
}
#endif
