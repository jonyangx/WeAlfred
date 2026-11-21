import AppKit
import SwiftUI
import Testing
@testable import WeAlfred

@MainActor
struct LauncherViewTests {
    @Test func focusedSearchFieldOpensAPathWithReturnAndHandlesEscape() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var opened: [URL] = []
        var dismissCount = 0
        var searchField: NSTextField?
        let model = LauncherModel {
            opened.append($0)
            return true
        }
        let view = LauncherView(
            model: model, shortcut: nil,
            registerField: { searchField = $0 },
            dismiss: { dismissCount += 1 }
        )

        _ = NSApplication.shared
        let panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 694, height: 77),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        panel.openResult = { index in
            guard model.results.indices.contains(index) else { return false }
            model.openResult(at: index)
            return true
        }
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        let field = try #require(searchField)
        #expect(panel.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        #expect(panel.firstResponder === editor)

        editor.insertText(directory.path, replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.query == directory.path)
        editor.keyDown(with: try keyDown("\r", keyCode: 36, in: panel))

        for _ in 0..<200 where model.isSearching {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(opened.map(\.path) == [directory.path])

        let shortcut = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "1",
            charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18
        ))
        #expect(panel.performKeyEquivalent(with: shortcut))
        #expect(opened.map(\.path) == [directory.path, directory.path])
        model.openResult(at: 8)
        #expect(opened.count == 2)

        editor.keyDown(with: try keyDown("\u{1b}", keyCode: 53, in: panel))
        #expect(dismissCount == 1)
    }

    private func keyDown(_ character: String, keyCode: UInt16, in panel: NSPanel) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode
        ))
    }
}
