import Darwin
import Foundation

enum ItemKind: String, CaseIterable, Sendable {
    case application, file, folder

    var title: String {
        switch self {
        case .application: "应用"
        case .file: "文件"
        case .folder: "目录"
        }
    }

    var symbol: String {
        switch self {
        case .application: "app.fill"
        case .file: "doc"
        case .folder: "folder.fill"
        }
    }
}

struct SearchItem: Identifiable, Sendable {
    static let attributes: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .localizedNameKey, .creationDateKey,
    ]

    let url: URL
    let name: String
    let kind: ItemKind
    let names: [String]
    let createdAt: Date?

    var id: String { url.path }

    /// Whether the item was created on or after `date`; items without a creation date never qualify.
    func isCreated(onOrAfter date: Date) -> Bool {
        (createdAt ?? .distantPast) >= date
    }

    init?(url: URL) {
        guard let entry = try? url.resourceValues(forKeys: Self.attributes) else { return nil }
        let target: URLResourceValues
        let targetURL: URL
        if entry.isSymbolicLink == true {
            let resolved = url.resolvingSymlinksInPath()
            guard resolved != url, let values = try? resolved.resourceValues(forKeys: Self.attributes) else {
                return nil
            }
            target = values
            targetURL = resolved
        } else {
            target = entry
            targetURL = url
        }

        guard let isDirectory = target.isDirectory else { return nil }
        if isDirectory && targetURL.pathExtension.lowercased() == "app" {
            kind = .application
        } else {
            kind = isDirectory && target.isPackage != true ? .folder : .file
        }
        self.url = URL(fileURLWithPath: url.path, isDirectory: target.isDirectory == true)
        let filename = url.lastPathComponent
        let displayName = entry.localizedName ?? filename
        name = kind == .application && (displayName as NSString).pathExtension.lowercased() == "app"
            ? (displayName as NSString).deletingPathExtension : displayName
        // Applications also match their Latin names from the bundle manifest,
        // so "we" finds 企业微信 (WeCom) and 微信读书 (wereader) behind localized bundle names.
        var candidates = [name, filename]
        if kind == .application { candidates += Catalog.applicationAliases(of: targetURL) }
        names = candidates.map(Catalog.fold)
        createdAt = target.creationDate
    }
}

enum Catalog {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static let applicationFolders = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        home.appendingPathComponent("Applications", isDirectory: true),
    ]

    static func applications(ownBundleURL: URL = Bundle.main.bundleURL) -> [SearchItem] {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app", isDirectory: true)
        return excludingSelf(
            unique(applicationFolders.flatMap { scan($0) }.filter { $0.kind == .application }
                + [SearchItem(url: finder)].compactMap { $0 }),
            ownBundleURL: ownBundleURL
        )
    }

    static func documents(
        additionalFolders: [URL], home: URL = Catalog.home, ownBundleURL: URL = Bundle.main.bundleURL
    ) -> [SearchItem] {
        let defaults = ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }
        let roots = Set((defaults + additionalFolders).map(canonicalDirectory))
        let contents = roots.flatMap { scan($0, includeRoot: true) }
        return excludingSelf(unique(contents + scan(home, recursively: false)), ownBundleURL: ownBundleURL)
    }

    static func path(from input: String, home: URL = Catalog.home) -> URL? {
        let path: String
        if input == "~" {
            path = home.path
        } else if input.hasPrefix("~/") {
            path = home.path + String(input.dropFirst())
        } else if input.hasPrefix("/") {
            path = input
        } else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    static func matches(
        _ input: String, kind: ItemKind?, in items: [SearchItem], limit: Int = 60,
        usage: [String: Int] = [:], now: Date = Date()
    ) -> [SearchItem] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPath = path(from: query) {
            if query != input, let rawPath = path(from: input), let item = SearchItem(url: rawPath) { return [item] }
            return [SearchItem(url: trimmedPath)].compactMap { $0 }
        }

        let key = fold(query)
        guard !key.isEmpty else { return [] }

        var ranked: [(item: SearchItem, rank: Int)] = []
        var seen: Set<String> = []
        for item in items {
            if Task.isCancelled { return [] }
            guard kind == nil || item.kind == kind else { continue }
            if let rank = item.names.compactMap({ matchRank($0, key: key) }).min(),
               seen.insert(item.id).inserted {
                ranked.append((item, rank))
            }
        }

        let today = Calendar.current.startOfDay(for: now)
        ranked.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            // Items created today come first, then frequently launched applications,
            // then applications ahead of files and folders (files and folders weigh the same).
            let lNew = lhs.item.isCreated(onOrAfter: today)
            let rNew = rhs.item.isCreated(onOrAfter: today)
            if lNew != rNew { return lNew }
            let lUse = lhs.item.kind == .application ? usage[lhs.item.id] ?? 0 : 0
            let rUse = rhs.item.kind == .application ? usage[rhs.item.id] ?? 0 : 0
            if lUse != rUse { return lUse > rUse }
            if (lhs.item.kind == .application) != (rhs.item.kind == .application) {
                return lhs.item.kind == .application
            }
            let byName = lhs.item.name.localizedStandardCompare(rhs.item.name)
            return byName == .orderedSame ? lhs.item.id < rhs.item.id : byName == .orderedAscending
        }
        return ranked.prefix(max(0, limit)).map(\.item)
    }

    static func fold(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    static func canonicalDirectory(_ url: URL) -> URL {
        // Match DirectoryEnumerator's physical paths, including macOS aliases such as /var.
        guard let path = realpath(url.path, nil) else { return url }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    private static let aliasKeys = ["CFBundleDisplayName", "CFBundleName", "CFBundleExecutable"]

    static func applicationAliases(of bundleURL: URL) -> [String] {
        let info = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: info) as? [String: Any] else { return [] }
        var aliases = aliasKeys.compactMap { dict[$0] as? String }
        if let identifier = dict["CFBundleIdentifier"] as? String {
            aliases.append(identifier)
            if let last = identifier.split(separator: ".").last { aliases.append(String(last)) }
        }
        return aliases
    }

    private static func excludingSelf(_ items: [SearchItem], ownBundleURL: URL) -> [SearchItem] {
        // Search must not offer the launcher itself; pasting its path still opens it.
        guard ownBundleURL.pathExtension.lowercased() == "app" else { return items }
        let ownPath = canonicalDirectory(ownBundleURL).path
        return items.filter { $0.url.path != ownPath }
    }

    private static func matchRank(_ name: String, key: String) -> Int? {
        if name == key { return 0 }
        if name.hasPrefix(key) { return 1 }
        if name.contains(key) { return 2 }
        return nil
    }

    private static func scan(_ root: URL, recursively: Bool = true, includeRoot: Bool = false) -> [SearchItem] {
        let root = canonicalDirectory(root)
        guard !Task.isCancelled, let rootItem = SearchItem(url: root), rootItem.kind == .folder else { return [] }

        var flags: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursively { flags.insert(.skipsSubdirectoryDescendants) }
        let urls = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(SearchItem.attributes), options: flags,
            errorHandler: { _, _ in true }
        )
        guard let urls else { return [] }

        var items = includeRoot ? [rootItem] : []
        for case let url as URL in urls {
            if Task.isCancelled { return [] }
            guard let item = SearchItem(url: url) else { continue }
            if item.kind != .folder { urls.skipDescendants() }
            items.append(item)
        }
        return items
    }

    private static func unique(_ items: [SearchItem]) -> [SearchItem] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }
}
