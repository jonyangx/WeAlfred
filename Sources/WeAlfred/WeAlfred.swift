import AppKit
import Combine
import SwiftUI

@main
struct WeAlfred {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = LauncherDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class LauncherPanel: NSPanel {
    var openResult: ((Int) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, modifiers == .command,
           let characters = event.charactersIgnoringModifiers, characters.count == 1,
           let number = Int(characters), (1...9).contains(number),
           openResult?(number - 1) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class LauncherDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = LauncherModel()
    private let folderKey = "searchFolders"
    private let panel = LauncherPanel(
        contentRect: NSRect(x: 0, y: 0, width: 694, height: 77),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    private var statusItem: NSStatusItem?
    private var shortcut: String?
    private weak var searchField: NSTextField?
    private lazy var hotKey = HotKey { [weak self] in self?.toggleLauncher() }
    private var isPresenting = false
    private var panelSizeSubscription: AnyCancellable?

    private var additionalFolders: [URL] {
        get { (UserDefaults.standard.stringArray(forKey: folderKey) ?? []).map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue.map(\.path), forKey: folderKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcut = hotKey.register()
        installEditMenu()
        configurePanel()
        installMenu()
        showLauncher()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncher()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusSearch()
    }

    func windowDidResignKey(_ notification: Notification) {
        dismissLauncher()
    }

    private func configurePanel() {
        panel.title = "WeAlfred"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let view = LauncherView(
            model: model, shortcut: shortcut,
            registerField: { [weak self] field in
                self?.searchField = field
                Task { @MainActor [weak self] in self?.focusSearch() }
            },
            dismiss: { [weak self] in self?.dismissLauncher() }
        )
        panel.contentView = NSHostingView(rootView: view)
        model.onOpen = { [weak self] in self?.dismissLauncher() }
        panel.openResult = { [weak self] index in
            guard let self, self.model.results.indices.contains(index) else { return false }
            self.model.openResult(at: index)
            return true
        }
        panelSizeSubscription = model.$results.combineLatest(model.$error)
            .sink { [weak self] results, error in
                self?.resizePanel(resultCount: results.count, hasError: error != nil)
            }
    }

    private func resizePanel(resultCount: Int, hasError: Bool) {
        let listHeight = resultCount == 0 ? 0 : CGFloat(resultCount * 44 + 11)
        let height = 77 + listHeight + (hasError ? 32 : 0)
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func installEditMenu() {
        let main = NSMenu()
        let edit = NSMenuItem()
        let actions = NSMenu(title: "编辑")
        actions.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        actions.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        actions.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        actions.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(edit)
        main.setSubmenu(actions, for: edit)
        NSApp.mainMenu = main
    }

    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "WeAlfred")
        image?.isTemplate = true
        item.button?.image = image
        if image == nil { item.button?.title = "W" }
        item.button?.toolTip = "WeAlfred"
        statusItem = item
        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()
        let open = menuItem("打开 WeAlfred", action: #selector(showLauncher))
        if let shortcut { open.title += "  \(shortcut)" }
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(menuItem("添加搜索目录…", action: #selector(chooseFolder)))
        if !additionalFolders.isEmpty {
            let remove = NSMenuItem(title: "移除搜索目录", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for folder in additionalFolders {
                let item = menuItem((folder.path as NSString).abbreviatingWithTildeInPath, action: #selector(removeFolder(_:)))
                item.representedObject = folder.path
                submenu.addItem(item)
            }
            remove.submenu = submenu
            menu.addItem(remove)
        }
        menu.addItem(menuItem("刷新搜索索引", action: #selector(refreshIndex)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 WeAlfred", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem?.menu = menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showLauncher() {
        guard NSApp.modalWindow == nil else { return }
        if !isPresenting {
            positionPanel()
            model.refresh(additionalFolders: additionalFolders)
        }
        isPresenting = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        focusSearch()
    }

    private func toggleLauncher() {
        if panel.isKeyWindow { dismissLauncher() } else { showLauncher() }
    }

    private func dismissLauncher() {
        guard isPresenting else { return }
        isPresenting = false
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        model.reset()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + (frame.height - size.height) * 0.64))
    }

    private func focusSearch() {
        guard panel.isKeyWindow, let searchField, searchField.window === panel else { return }
        panel.makeFirstResponder(searchField)
    }

    @objc private func chooseFolder() {
        dismissLauncher()
        NSApp.activate()
        let picker = NSOpenPanel()
        picker.title = "添加搜索目录"
        picker.prompt = "添加"
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.allowsMultipleSelection = true
        picker.canCreateDirectories = false
        guard picker.runModal() == .OK else { return }
        var folders = additionalFolders
        for url in picker.urls {
            let folder = url.resolvingSymlinksInPath().standardizedFileURL
            if !folders.contains(where: { $0.path == folder.path }) { folders.append(folder) }
        }
        additionalFolders = folders
        updateMenu()
        refreshIndex()
        showLauncher()
    }

    @objc private func removeFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        additionalFolders = additionalFolders.filter { $0.path != path }
        updateMenu()
        refreshIndex()
    }

    @objc private func refreshIndex() {
        model.refresh(additionalFolders: additionalFolders, force: true)
    }
}
