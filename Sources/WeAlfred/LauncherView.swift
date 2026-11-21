import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.colorScheme) private var colorScheme
    let shortcut: String?
    let registerField: (NSTextField) -> Void
    let dismiss: () -> Void

    private let accent = Color(red: 0.0, green: 0.54, blue: 0.46)

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !model.results.isEmpty {
                Divider()
                VStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        resultRow(item, index: index)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(1)
                    .help(error)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            SearchField(model: model, registerField: registerField, dismiss: dismiss)
                .padding(.horizontal, 12)
                .frame(height: 54)
                .background { fieldFill }
            Image(systemName: "command.square.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(accent)
                .accessibilityLabel(status)
                .help(status)
        }
        .padding(.horizontal, 8)
        .frame(height: 77)
    }

    /// The input area is its own bar, a clearly darker shade than the panel background.
    private var fieldFill: some View {
        let base = colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.07)
            : Color(red: 0.82, green: 0.82, blue: 0.82)
        let edge = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.15)
        return RoundedRectangle(cornerRadius: 12)
            .fill(base)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(edge))
    }

    private var status: String {
        if model.isSearching || model.isIndexingCurrentFilter { return "正在搜索" }
        if !model.trimmedQuery.isEmpty && model.results.isEmpty {
            return Catalog.path(from: model.trimmedQuery) == nil ? "没有匹配的项目" : "路径不存在或无法访问"
        }
        return "WeAlfred · \(shortcut ?? "从菜单栏打开")"
    }

    private func resultRow(_ item: SearchItem, index: Int) -> some View {
        let selected = model.selection == item.id
        return Button {
            model.open(item)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if item.kind == .application {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().scaledToFit()
                    } else {
                        Image(systemName: item.kind.symbol).font(.system(size: 16)).foregroundStyle(accent)
                    }
                }
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 10)
                Text("⌘\(index + 1)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(selected ? accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SearchField: NSViewRepresentable {
    @ObservedObject var model: LauncherModel
    let registerField: (NSTextField) -> Void
    let dismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = .systemFont(ofSize: 28)
        field.placeholderString = "搜索或输入路径"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.delegate = context.coordinator
        field.setAccessibilityLabel("搜索或输入路径")
        registerField(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != model.query { field.stringValue = model.query }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.model.setQuery(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.model.moveSelection(by: -1)
            case #selector(NSResponder.moveDown(_:)): parent.model.moveSelection(by: 1)
            case #selector(NSResponder.insertNewline(_:)): parent.model.openSelection()
            case #selector(NSResponder.cancelOperation(_:)): parent.dismiss()
            default: return false
            }
            return true
        }
    }
}
