import AppKit
import SwiftUI

/// Panels Claude draws (#35, PLAN.md §4): a card, a table or choices, in one floating panel beside the character.
/// The content comes from the core's `ui` tools and is shown verbatim. A new panel replaces the old one; it stays
/// until I close it or Claude dismisses it. It never takes focus and is static when nothing changes.
struct PanelContent: Equatable {
    enum Kind: String { case card, table, choices }
    var id: String
    var kind: Kind
    var title: String
    var body = ""                       // card (markdown)
    var columns: [String] = []          // table
    var rows: [[String]] = []
    var truncatedRows = 0
    var options: [String] = []          // choices

    init?(message m: [String: Any]) {
        guard let id = m["id"] as? String, let k = Kind(rawValue: m["kind"] as? String ?? ""),
              let p = m["payload"] as? [String: Any] else { return nil }
        self.id = id; kind = k
        title = (p["title"] as? String) ?? (p["prompt"] as? String) ?? ""
        body = p["body"] as? String ?? ""
        columns = p["columns"] as? [String] ?? []
        rows = (p["rows"] as? [[Any]] ?? []).map { $0.map { "\($0)" } }
        truncatedRows = p["truncated_rows"] as? Int ?? 0
        options = p["options"] as? [String] ?? []
    }

    /// Tab-separated text for the clipboard.
    var tsv: String {
        ([columns] + rows).map { $0.map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\t") }.joined(separator: "\n")
    }
}

@MainActor @Observable
final class PanelState {
    var sortColumn: Int? = nil
    var ascending = true
    var copied = false
}

struct PanelView: View {
    let content: PanelContent
    let state: PanelState
    var height: CGFloat
    var onClose: () -> Void
    var onChoice: (String) -> Void
    var onCopy: () -> Void

    static let width: CGFloat = 520
    static let maxHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(content.title).font(.headline).lineLimit(2)
                Spacer()
                if content.kind == .table {
                    Button(state.copied ? "Copied" : "Copy") { onCopy() }.help("Copy as tab-separated text")
                }
                Button { onClose() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            switch content.kind {
            case .card:
                ScrollView {
                    Text(BubbleView.markdown(content.body)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: height)
            case .table:
                table
            case .choices:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(content.options.enumerated()), id: \.offset) { _, o in
                        Button { onChoice(o) } label: {
                            Text(o).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5).padding(.horizontal, 8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(6)
    }

    private var sortedRows: [[String]] {
        guard let c = state.sortColumn else { return content.rows }
        let s = content.rows.sorted {
            let a = $0.indices.contains(c) ? $0[c] : "", b = $1.indices.contains(c) ? $1[c] : ""
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return state.ascending ? s : s.reversed()
    }

    private var table: some View {
        let colWidth = max(90, (Self.width - 24) / CGFloat(max(1, content.columns.count)))
        return ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header:
                    HStack(spacing: 0) {
                        ForEach(Array(content.columns.enumerated()), id: \.offset) { i, c in
                            Button {
                                if state.sortColumn == i { state.ascending.toggle() } else { state.sortColumn = i; state.ascending = true }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(c).font(.caption.bold()).lineLimit(1)
                                    if state.sortColumn == i { Image(systemName: state.ascending ? "chevron.up" : "chevron.down").font(.caption2) }
                                }
                                .frame(width: colWidth, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                ) {
                    ForEach(Array(sortedRows.enumerated()), id: \.offset) { n, r in
                        HStack(spacing: 0) {
                            ForEach(Array(r.enumerated()), id: \.offset) { _, cell in
                                Text(cell).font(.callout).lineLimit(2).textSelection(.enabled)
                                    .frame(width: colWidth, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 3)
                        .background(n % 2 == 1 ? Color.primary.opacity(0.04) : .clear)
                    }
                    if content.truncatedRows > 0 {
                        Text("… \(content.truncatedRows) more rows not shown").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

@MainActor
final class PanelWindow {
    let panel: NSPanel
    private let host: NSHostingView<PanelView>
    private let state = PanelState()
    private(set) var content: PanelContent?
    private weak var anchor: NSWindow?
    /// A click on a choice: my next turn.
    var onChoice: ((String) -> Void)?

    init(anchor: NSWindow) {
        self.anchor = anchor
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 200),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        host = NSHostingView(rootView: PanelView(content: PanelContent.placeholder, state: state, height: 100,
                                                 onClose: {}, onChoice: { _ in }, onCopy: {}))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show(_ c: PanelContent) {
        content = c
        state.sortColumn = nil; state.ascending = true; state.copied = false
        layout()
    }

    func dismiss(_ id: String) { if content?.id == id { close() } }

    func close() {
        content = nil
        panel.orderOut(nil)
    }

    private func layout() {
        guard let c = content, let a = anchor else { return }
        // Body height: tables by row count; cards by their text; choices fit.
        let bodyHeight: CGFloat
        switch c.kind {
        case .table: bodyHeight = min(PanelView.maxHeight, CGFloat(c.rows.count + 1) * 26 + (c.truncatedRows > 0 ? 24 : 8))
        case .card:
            let probe = NSHostingView(rootView: Text(BubbleView.markdown(c.body)).frame(width: PanelView.width - 24, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true))
            bodyHeight = min(PanelView.maxHeight, probe.fittingSize.height + 4)
        case .choices: bodyHeight = 0
        }
        let view = PanelView(content: c, state: state, height: bodyHeight,
                             onClose: { [weak self] in self?.close() },
                             onChoice: { [weak self] o in self?.close(); self?.onChoice?(o) },
                             onCopy: { [weak self] in
                                 guard let self, let c = self.content else { return }
                                 NSPasteboard.general.clearContents()
                                 NSPasteboard.general.setString(c.tsv, forType: .string)
                                 self.state.copied = true
                             })
        let size = NSHostingView(rootView: view).fittingSize
        host.rootView = view
        // Beside the character: to its left (or right, near the left edge), bottom-aligned, kept on screen.
        let screen = (a.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let af = a.frame
        var x = af.minX - size.width + 10
        if x < screen.minX + 8 { x = af.maxX - 10 }
        var y = af.minY
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

extension PanelContent {
    static let placeholder = PanelContent(message: ["id": "-", "kind": "card", "payload": ["title": "", "body": ""]])!
}
