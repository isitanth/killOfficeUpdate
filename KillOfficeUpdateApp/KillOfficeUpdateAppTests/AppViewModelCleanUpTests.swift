import XCTest
@testable import KillOfficeUpdateApp

@MainActor
final class AppViewModelCleanUpTests: XCTestCase {

    private var tmpDir: URL!
    private var logFilePath: URL!
    private var stdoutPath: String!
    private var stderrPath: String!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("killmau-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        logFilePath = tmpDir.appendingPathComponent("killmau.log")
        stdoutPath = tmpDir.appendingPathComponent("stdout.log").path
        stderrPath = tmpDir.appendingPathComponent("stderr.log").path
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func makeViewModel() -> AppViewModel {
        AppViewModel(
            installDir: tmpDir,
            logFilePath: logFilePath,
            tmpStdoutPath: stdoutPath,
            tmpStderrPath: stderrPath,
            performSetup: false
        )
    }

    // MARK: - Guard tests

    func test_cleanUp_blockedWhenBusy() throws {
        try "original content".write(to: logFilePath, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.isInstalled = true
        vm.isBusy = true
        vm.logEntries = ["entry1"]
        vm.statusMessage = "some status"

        vm.cleanUp()

        // Nothing should have changed
        let content = try String(contentsOf: logFilePath, encoding: .utf8)
        XCTAssertEqual(content, "original content")
        XCTAssertEqual(vm.logEntries, ["entry1"])
        XCTAssertEqual(vm.statusMessage, "some status")
        XCTAssertTrue(vm.isBusy, "isBusy should remain true — guard returned early")
    }

    func test_cleanUp_blockedWhenNotInstalled() throws {
        try "original content".write(to: logFilePath, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.isInstalled = false
        vm.logEntries = ["entry1"]
        vm.statusMessage = "some status"

        vm.cleanUp()

        let content = try String(contentsOf: logFilePath, encoding: .utf8)
        XCTAssertEqual(content, "original content")
        XCTAssertEqual(vm.logEntries, ["entry1"])
        XCTAssertEqual(vm.statusMessage, "some status")
        XCTAssertFalse(vm.isBusy, "isBusy should remain false — guard returned early")
    }

    // MARK: - Log file truncation

    func test_cleanUp_truncatesLogFile() throws {
        try "line1\nline2\nline3\n".write(to: logFilePath, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFilePath.path),
                       "Log file must still exist — truncated, not deleted")
        let content = try String(contentsOf: logFilePath, encoding: .utf8)
        XCTAssertEqual(content, "", "Log file should be empty after truncation")
    }

    func test_cleanUp_handlesNonexistentLogFile() {
        // Log file does not exist — cleanUp should not crash or create it
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertFalse(FileManager.default.fileExists(atPath: logFilePath.path),
                        "Log file should not be created if it didn't exist")
        XCTAssertEqual(vm.statusMessage, "Cleaned up successfully")
    }

    func test_cleanUp_handlesEmptyLogFile() throws {
        try "".write(to: logFilePath, atomically: true, encoding: .utf8)
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertTrue(FileManager.default.fileExists(atPath: logFilePath.path))
        let content = try String(contentsOf: logFilePath, encoding: .utf8)
        XCTAssertEqual(content, "")
    }

    // MARK: - Temp file deletion

    func test_cleanUp_deletesStdoutTempFile() {
        FileManager.default.createFile(atPath: stdoutPath, contents: Data("stdout data".utf8))
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stdoutPath))
    }

    func test_cleanUp_deletesStderrTempFile() {
        FileManager.default.createFile(atPath: stderrPath, contents: Data("stderr data".utf8))
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stderrPath))
    }

    func test_cleanUp_deletesBothTempFiles() {
        FileManager.default.createFile(atPath: stdoutPath, contents: Data("out".utf8))
        FileManager.default.createFile(atPath: stderrPath, contents: Data("err".utf8))
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stdoutPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stderrPath))
    }

    func test_cleanUp_handlesMissingTempFiles() {
        // Neither temp file exists — should not crash
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertEqual(vm.statusMessage, "Cleaned up successfully")
    }

    // MARK: - State updates

    func test_cleanUp_clearsLogEntries() {
        let vm = makeViewModel()
        vm.isInstalled = true
        vm.logEntries = ["[2026-03-09] Killed MAU", "[2026-03-09] Watchdog started"]

        vm.cleanUp()

        XCTAssertTrue(vm.logEntries.isEmpty)
    }

    func test_cleanUp_setsStatusMessage() {
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertEqual(vm.statusMessage, "Cleaned up successfully")
    }

    func test_cleanUp_resetsBusyFlag() {
        let vm = makeViewModel()
        vm.isInstalled = true

        vm.cleanUp()

        XCTAssertFalse(vm.isBusy)
    }

    // MARK: - Full scenario

    func test_cleanUp_fullScenario() throws {
        // Setup: all files exist, log has content, entries populated
        try "[2026-03-09 12:00:00] Watchdog started\n[2026-03-09 12:00:03] Killed MAU\n"
            .write(to: logFilePath, atomically: true, encoding: .utf8)
        FileManager.default.createFile(atPath: stdoutPath, contents: Data("stdout".utf8))
        FileManager.default.createFile(atPath: stderrPath, contents: Data("stderr".utf8))

        let vm = makeViewModel()
        vm.isInstalled = true
        vm.logEntries = ["entry1", "entry2"]
        vm.statusMessage = "Active"

        vm.cleanUp()

        // Log file truncated (not deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFilePath.path))
        let content = try String(contentsOf: logFilePath, encoding: .utf8)
        XCTAssertEqual(content, "")

        // Temp files deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: stdoutPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stderrPath))

        // State updated
        XCTAssertTrue(vm.logEntries.isEmpty)
        XCTAssertEqual(vm.statusMessage, "Cleaned up successfully")
        XCTAssertFalse(vm.isBusy)
    }
}
