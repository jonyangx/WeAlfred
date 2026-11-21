import AppKit
import Combine

@MainActor
final class LauncherModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var filter: ItemKind?
    @Published private(set) var results: [SearchItem] = []
    @Published private(set) var selection: String?
    @Published private(set) var isSearching = false
    @Published private(set) var isIndexingApplications = false
    @Published private(set) var isIndexingDocuments = false
    @Published private(set) var error: String?

    var onOpen: (() -> Void)?

    private let openURL: (URL) -> Bool
    private let usageDefaults: UserDefaults
    private var applications: [SearchItem] = []
    private var documents: [SearchItem] = []
    private var scanApplications: Task<Void, Never>?
    private var scanDocuments: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var openPathWhenReady = false
    private var lastRefresh: Date?
    private var indexedFolders: [URL] = []

    init(
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        usageDefaults: UserDefaults = .standard
    ) {
        self.openURL = openURL
        self.usageDefaults = usageDefaults
    }

    var isIndexingCurrentFilter: Bool {
        Catalog.path(from: trimmedQuery) == nil && (isIndexingDocuments || (includesApplications && isIndexingApplications))
    }

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var includesApplications: Bool { filter == nil || filter == .application }

    func refresh(additionalFolders: [URL], force: Bool = false) {
        if !force, let lastRefresh,
           isIndexingApplications || isIndexingDocuments || Date().timeIntervalSince(lastRefresh) < 20 {
            return
        }

        lastRefresh = Date()
        scanApplications?.cancel()
        scanDocuments?.cancel()
        isIndexingApplications = true
        isIndexingDocuments = true
        if indexedFolders != additionalFolders {
            indexedFolders = additionalFolders
            documents = []
            searchAfterIndexing()
        }

        scanApplications = Task.detached(priority: .userInitiated) { [weak self] in
            let items = Catalog.applications()
            await self?.setApplications(items)
        }
        scanDocuments = Task.detached(priority: .utility) { [weak self] in
            let items = Catalog.documents(additionalFolders: additionalFolders)
            await self?.setDocuments(items)
        }
    }

    func setQuery(_ value: String) {
        guard query != value else { return }
        query = value
        clearResults()
        search(debounce: true)
    }

    func setFilter(_ value: ItemKind?) {
        guard filter != value else { return }
        filter = value
        clearResults()
        search()
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        filter = nil
        isSearching = false
        clearResults()
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selection } ?? 0
        let next = min(max(current + offset, 0), results.count - 1)
        selection = results[next].id
    }

    func openResult(at index: Int) {
        guard results.indices.contains(index) else { return }
        open(results[index])
    }

    func openSelection() {
        guard let item = results.first(where: { $0.id == selection }) else {
            // Return can arrive immediately after pasting a path, while its lookup is still running.
            openPathWhenReady = isSearching && Catalog.path(from: trimmedQuery) != nil
            return
        }
        open(item)
    }

    func open(_ item: SearchItem) {
        guard FileManager.default.fileExists(atPath: item.url.path), openURL(item.url) else {
            error = "无法打开「\(item.name)」。项目可能已移动，或当前没有访问权限。"
            return
        }
        if item.kind == .application { UsageLog.record(item.id, in: usageDefaults) }
        onOpen?()
    }

    private func clearResults() {
        openPathWhenReady = false
        results = []
        selection = nil
        error = nil
    }

    private func setApplications(_ items: [SearchItem]) {
        guard !Task.isCancelled else { return }
        applications = items
        isIndexingApplications = false
        if includesApplications { searchAfterIndexing() }
    }

    private func setDocuments(_ items: [SearchItem]) {
        guard !Task.isCancelled else { return }
        documents = items
        isIndexingDocuments = false
        searchAfterIndexing()
    }

    private func searchAfterIndexing() {
        if Catalog.path(from: trimmedQuery) == nil { search() }
    }

    private func search(debounce: Bool = false) {
        searchTask?.cancel()
        guard !trimmedQuery.isEmpty else {
            isSearching = false
            return
        }
        isSearching = true
        let query = query
        let filter = filter
        let applications = includesApplications ? applications : []
        let documents = documents
        let usage = UsageLog.counts(in: usageDefaults)
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled else { return }
            let items = applications.isEmpty ? documents : applications + documents
            let results = Catalog.matches(query, kind: filter, in: items, limit: 9, usage: usage)
            await self?.setResults(results)
        }
    }

    private func setResults(_ items: [SearchItem]) {
        guard !Task.isCancelled else { return }
        results = items
        if !items.contains(where: { $0.id == selection }) { selection = items.first?.id }
        isSearching = false
        if openPathWhenReady {
            openPathWhenReady = false
            openSelection()
        }
    }
}
