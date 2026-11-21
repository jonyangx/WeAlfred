import Foundation
import Testing
@testable import WeAlfred

@MainActor
struct LauncherModelTests {
    @Test func selectingExactPathForEachTypePassesItToTheSystemOpener() async throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Notes.txt")
        try Data().write(to: file)

        var opened: [URL] = []
        var successCount = 0
        let usage = isolatedDefaults()
        defer { usage.defaults.removePersistentDomain(forName: usage.suite) }
        let model = LauncherModel(openURL: {
            opened.append($0)
            return true
        }, usageDefaults: usage.defaults)
        model.onOpen = { successCount += 1 }

        for (url, kind) in [(app, ItemKind.application), (file, .file), (dir, .folder)] {
            model.setQuery(url.path)
            try await waitForSearch(model)
            #expect(model.results.first?.kind == kind)
            #expect(model.selection == url.path)
            model.openSelection()
        }
        #expect(opened.map(\.path) == [app.path, file.path, dir.path])
        #expect(successCount == 3)
    }

    @Test func deletedItemAndWorkspaceFailureKeepTheLauncherOpen() async throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("temporary.txt")
        try Data().write(to: file)

        var attempts = 0
        let model = LauncherModel { _ in
            attempts += 1
            return false
        }
        model.onOpen = { Issue.record("The launcher closed after a failed open") }
        model.setQuery(file.path)
        try await waitForSearch(model)

        model.openSelection()
        #expect(model.error != nil)
        #expect(attempts == 1)
        try FileManager.default.removeItem(at: file)
        model.openSelection()
        #expect(attempts == 1)
        #expect(model.selection == file.path)
        model.reset()
        #expect(model.error == nil)
        #expect(model.selection == nil)
    }

    @Test func returnImmediatelyAfterPastingAPathOpensTheResultOnce() async throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("My Notes.txt")
        try Data().write(to: file)

        var opened: [URL] = []
        let model = LauncherModel {
            opened.append($0)
            return true
        }

        model.setQuery(file.path)
        model.openSelection()
        model.openSelection()
        try await waitForSearch(model)
        #expect(opened.map(\.path) == [file.path])

        model.setQuery(dir.path)
        model.openSelection()
        model.setQuery(file.path)
        try await waitForSearch(model)
        #expect(opened.count == 1)
    }

    @Test func rapidEditsCannotOpenAStaleResult() async throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = LauncherModel { _ in
            Issue.record("Opened a stale item")
            return true
        }
        model.setQuery(dir.path)
        try await waitForSearch(model)
        #expect(model.selection != nil)

        model.setQuery(dir.appendingPathComponent("missing").path)
        model.openSelection()
        try await waitForSearch(model)
        #expect(model.results.isEmpty)
        model.setQuery(dir.path)
        model.openSelection()
        model.reset()
        try await Task.sleep(for: .milliseconds(120))
        #expect(model.results.isEmpty)
        #expect(!model.isSearching)
    }

    @Test func openingAnApplicationMovesItUpInLaterSearches() async throws {
        // The index canonicalizes directories with realpath, so rank the fixture by its physical path.
        let dir = Catalog.canonicalDirectory(try fixtureDirectory())
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try makeApp("zzq One.app", in: dir)
        let second = try makeApp("zzq Two.app", in: dir)

        let usage = isolatedDefaults()
        defer { usage.defaults.removePersistentDomain(forName: usage.suite) }
        let model = LauncherModel(openURL: { _ in true }, usageDefaults: usage.defaults)
        model.refresh(additionalFolders: [dir], force: true)
        try await waitForIndexing(model)

        model.setQuery("zzq")
        try await waitForSearch(model)
        #expect(model.results.map(\.id) == [first.path, second.path])

        model.setQuery(second.path)
        try await waitForSearch(model)
        model.openSelection()

        model.setQuery("zzq")
        try await waitForSearch(model)
        #expect(model.results.map(\.id) == [second.path, first.path])
    }

    private func waitForSearch(_ model: LauncherModel) async throws {
        for _ in 0..<200 {
            if !model.isSearching { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Search did not finish")
    }

    private func waitForIndexing(_ model: LauncherModel) async throws {
        for _ in 0..<2000 {
            if !model.isIndexingApplications && !model.isIndexingDocuments { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Indexing did not finish")
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeApp(_ name: String, in directory: URL) throws -> URL {
        let app = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        return app
    }

    private func isolatedDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "WeAlfredTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}
