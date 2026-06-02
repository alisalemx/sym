import XCTest
@testable import Sym

final class SymlinkServiceTests: XCTestCase {
    private var root: URL!
    private var destination: URL!
    private var service: SymlinkService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        destination = root.appendingPathComponent("Links")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        service = SymlinkService()
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testCreatesSymlinkForFileSource() throws {
        let source = try makeFile(named: "notes.txt")

        let result = try service.createLinks(sources: [SourceItem(url: source)], in: destination)

        let linkURL = try XCTUnwrap(result.created.first)
        XCTAssertEqual(linkURL.lastPathComponent, "notes.txt")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path), source.path)
    }

    func testCreatesSymlinkForFolderSource() throws {
        let source = root.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let result = try service.createLinks(sources: [SourceItem(url: source)], in: destination)

        let linkURL = try XCTUnwrap(result.created.first)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path), source.path)
    }

    func testCreatesMultipleSymlinks() throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")

        let result = try service.createLinks(sources: [SourceItem(url: first), SourceItem(url: second)], in: destination)

        XCTAssertEqual(result.created.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("first.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("second.txt").path))
    }

    func testExistingDestinationPathBlocksValidation() throws {
        let source = try makeFile(named: "notes.txt")
        _ = try makeFile(named: "notes.txt", in: destination)

        let validation = service.validate(sources: [SourceItem(url: source)], destinationFolder: destination)

        XCTAssertFalse(try XCTUnwrap(validation.first).isValid)
    }

    func testMissingSourceBlocksValidation() throws {
        let missing = root.appendingPathComponent("missing.txt")

        let validation = service.validate(sources: [SourceItem(url: missing)], destinationFolder: destination)

        XCTAssertFalse(try XCTUnwrap(validation.first).isValid)
    }

    func testBatchCreationDoesNotPartiallyCreateWhenAnySourceConflicts() throws {
        let first = try makeFile(named: "first.txt")
        let second = try makeFile(named: "second.txt")
        _ = try makeFile(named: "second.txt", in: destination)

        XCTAssertThrowsError(
            try service.createLinks(sources: [SourceItem(url: first), SourceItem(url: second)], in: destination)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("first.txt").path))
    }

    func testCreatedSymlinkUsesAbsoluteDestinationPath() throws {
        let source = try makeFile(named: "absolute.txt")

        let result = try service.createLinks(sources: [SourceItem(url: source)], in: destination)

        let linkURL = try XCTUnwrap(result.created.first)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkURL.path), source.absoluteURL.path)
    }

    private func makeFile(named name: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? root).appendingPathComponent(name)
        try "fixture".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

