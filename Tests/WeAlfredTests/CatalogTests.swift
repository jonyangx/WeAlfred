import Foundation
import Testing
@testable import WeAlfred

final class CatalogTests {
    private let home: URL
    private let files = FileManager.default

    init() throws {
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        home = Catalog.canonicalDirectory(directory)
    }

    deinit {
        try? files.removeItem(at: home)
    }

    @Test func findsSystemApplicationsWithTheirInstalledNames() {
        let apps = Catalog.applications()
        #expect(Catalog.matches("Calculator", kind: .application, in: apps).contains { $0.url.lastPathComponent == "Calculator.app" })
        #expect(Catalog.matches("Finder", kind: .application, in: apps).contains { $0.url.lastPathComponent == "Finder.app" })
    }

    @Test func defaultAndAddedFoldersSearchWithoutSpotlight() throws {
        let document = try makeFile("Documents/测试项目/内部文件.txt")
        let desktop = try makeFile("Desktop/桌面.txt")
        let download = try makeFile("Downloads/下载.txt")
        let homeFile = try makeFile("主目录.txt")
        let hidden = try makeFile("Documents/.隐藏文件.txt")
        let external = try makeFile("Projects/工程文件.txt")
        let inHiddenFolder = try makeFile("Documents/.chosen/手动添加.txt")

        let defaults = Catalog.documents(additionalFolders: [], home: home)
        let defaultPaths = Set(defaults.map(\.id))
        for url in [document, desktop, download, homeFile] { #expect(defaultPaths.contains(url.path)) }
        for url in [external, hidden, inHiddenFolder] { #expect(!defaultPaths.contains(url.path)) }
        #expect(defaults.filter { $0.id == desktop.deletingLastPathComponent().path }.count == 1)

        let scopes = [external.deletingLastPathComponent(), inHiddenFolder.deletingLastPathComponent()]
        let withAddedFolders = Catalog.documents(additionalFolders: scopes, home: home)
        #expect(withAddedFolders.filter { $0.id == external.path }.count == 1)
        #expect(withAddedFolders.filter { $0.id == inHiddenFolder.path }.count == 1)
        #expect(Catalog.matches("测试项目", kind: .folder, in: defaults).first?.id == document.deletingLastPathComponent().path)
    }

    @Test func appBundleIsNotSearchedInternally() throws {
        let internalFile = try makeFile("Desktop/Example.app/Contents/MacOS/helper")
        let fakeApp = try makeFile("Desktop/fake.app")
        let items = Catalog.documents(additionalFolders: [], home: home)
        #expect(Catalog.matches("example.app", kind: .application, in: items).first?.name == "Example")
        #expect(Catalog.matches("fake.app", kind: .file, in: items).first?.id == fakeApp.path)
        #expect(!items.contains { $0.id == internalFile.path })
    }

    @Test func nameRankingTypeFilterAndLimit() throws {
        let urls = try ["Documents/Resume.txt", "Documents/Résumé", "Documents/My Resume.txt"].map { try makeFile($0) }
        let items = urls.compactMap(SearchItem.init) + urls.compactMap(SearchItem.init)
        #expect(Catalog.matches(" resume ", kind: nil, in: items).map(\.id) == [urls[1].path, urls[0].path, urls[2].path])
        #expect(Catalog.matches("ＲＥＳＵＭＥ", kind: .file, in: items, limit: 1).first?.id == urls[1].path)
        #expect(Catalog.matches("Resume", kind: .folder, in: items).isEmpty)
        #expect(Catalog.matches("  ", kind: nil, in: items).isEmpty)
    }

    @Test func exactPathWithSpacesOutsideSearchScope() throws {
        let document = try makeFile("unindexed/location/My Note.txt ")
        #expect(Catalog.matches(document.path, kind: .application, in: []).first?.id == document.path)
        #expect(Catalog.path(from: "~/unindexed", home: home)?.path == home.appendingPathComponent("unindexed").path)
        #expect(Catalog.path(from: "~", home: home)?.path == home.path)
        #expect(Catalog.path(from: "Documents/report") == nil)
        #expect(Catalog.matches(home.appendingPathComponent("missing").path, kind: nil, in: []).isEmpty)
    }

    @Test func symlinkCanOpenItsTargetAndMissingTargetIsExcluded() throws {
        let document = try makeFile("Documents/linked/target.txt")
        let link = home.appendingPathComponent("folder-link")
        try files.createSymbolicLink(at: link, withDestinationURL: document.deletingLastPathComponent())
        let item = try #require(Catalog.matches(link.path, kind: nil, in: []).first)
        #expect(item.kind == .folder)
        #expect(item.id == link.path)
        let broken = home.appendingPathComponent("broken-link")
        try files.createSymbolicLink(at: broken, withDestinationURL: home.appendingPathComponent("missing"))
        #expect(Catalog.matches(broken.path, kind: nil, in: []).isEmpty)
    }

    @Test func createdTodayOutranksFrequencyAndKind() throws {
        let popular = try makeDirectory("Documents/note-popular.app", createdDaysAgo: 3)
        let unused = try makeDirectory("Documents/note-unused.app", createdDaysAgo: 3)
        let oldFile = try makeFile("Documents/note-old.txt", createdDaysAgo: 3)
        let newFile = try makeFile("Documents/note-new-file.txt")
        let newFolder = try makeDirectory("Documents/note-new-dir")
        let items = Catalog.documents(additionalFolders: [], home: home)

        let order = Catalog.matches("note", kind: nil, in: items, usage: [popular.path: 5]).map(\.id)
        #expect(order == [newFolder.path, newFile.path, popular.path, unused.path, oldFile.path])
    }

    @Test func matchRankStillBeatsCreatedToday() throws {
        let rankedOld = try makeFile("Documents/notes.txt", createdDaysAgo: 3)
        let containsNew = try makeFile("Documents/my-notes.txt")
        let items = Catalog.documents(additionalFolders: [], home: home)
        let matches = Catalog.matches("notes", kind: nil, in: items)
        #expect(matches.first?.id == rankedOld.path)
        #expect(matches.contains { $0.id == containsNew.path })
    }

    @Test func latinAliasesMatchBehindLocalizedBundleNames() throws {
        let wereader = try makeApp("Documents/微信读书.app", executable: "wereader", identifier: "com.tencent.wereader")
        let wecom = try makeApp("Documents/企业微信.app", executable: "WeCom", identifier: "com.tencent.wecom")
        let unrelated = try makeApp("Documents/备忘录.app", executable: "notes", identifier: "local.notes")
        let items = Catalog.documents(additionalFolders: [], home: home)

        let we = Catalog.matches("we", kind: .application, in: items).map(\.id)
        #expect(Set(we) == [wereader.path, wecom.path])
        #expect(Catalog.matches("wereader", kind: .application, in: items).map(\.id) == [wereader.path])
        #expect(Catalog.matches("wecom", kind: .application, in: items).map(\.id) == [wecom.path])
        #expect(Catalog.matches("notes", kind: .application, in: items).map(\.id) == [unrelated.path])
        // Alias hits still present themselves with the localized display name.
        #expect(Catalog.matches("wereader", kind: .application, in: items).first?.name == "微信读书")
    }

    @Test func theLauncherItselfIsExcludedFromSearch() throws {
        let store = try makeDirectory("Applications")
        let own = try makeDirectory("Applications/WeAlfred.app")
        let other = try makeDirectory("Applications/Workspace.app")
        let items = Catalog.documents(additionalFolders: [store], home: home, ownBundleURL: own)

        let ids = Set(items.map(\.id))
        #expect(!ids.contains(own.path))
        #expect(ids.contains(other.path))
    }

    private func makeApp(
        _ relativePath: String, executable: String, identifier: String
    ) throws -> URL {
        let app = try makeDirectory(relativePath)
        try files.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>\(executable)</string>
        <key>CFBundleIdentifier</key><string>\(identifier)</string>
        </dict></plist>
        """
        try info.write(
            to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8
        )
        return app
    }

    private func makeFile(_ relativePath: String, createdDaysAgo: Double? = nil) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        try age(url, daysAgo: createdDaysAgo)
        return url
    }

    private func makeDirectory(_ relativePath: String, createdDaysAgo: Double? = nil) throws -> URL {
        let url = home.appendingPathComponent(relativePath, isDirectory: true)
        try files.createDirectory(at: url, withIntermediateDirectories: true)
        try age(url, daysAgo: createdDaysAgo)
        return url
    }

    private func age(_ url: URL, daysAgo: Double?) throws {
        guard let daysAgo else { return }
        try files.setAttributes(
            [.creationDate: Date(timeIntervalSinceNow: -daysAgo * 86_400)], ofItemAtPath: url.path
        )
    }
}
