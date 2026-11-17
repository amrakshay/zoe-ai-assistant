import AppKit
import SwiftUI

/// What the bubble shows (#6): what I said, then Zoe's reply as it streams. A long (summarised) reply
/// opens as a scrollable card with the full text (PLAN.md §5.12).
/// A plain value, so the panel can be measured synchronously from a fresh view.
struct BubbleContent: Equatable {
    var you = ""
    var reply = ""
    var card = false          // full reply in a scrollable card
}

@MainActor @Observable
final class BubbleHover { var on = false }

struct BubbleView: View {
    let model: BubbleContent
    let hover: BubbleHover
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.you.isEmpty {
                Text(model.you)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(model.card ? 2 : 3)
            }
            if !model.reply.isEmpty {
                if model.card {
                    ScrollView {
                        Text(Self.markdown(model.reply))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 260)          // a ScrollView doesn't report its content height
                } else {
                    Text(Self.markdown(model.reply))
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            }
        }
        .font(.body)
        .padding(12)
        .frame(width: model.card ? 380 : nil, alignment: .leading)
        .frame(maxWidth: 380, alignment: .leading)
        .fixedSize(horizontal: !model.card, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hover.on {
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).padding(5)
            }
        }
        .onHover { hover.on = $0 }
        .padding(6)   // room for the material's edge
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// The bubble's panel, placed next to the character and resized to fit its content.
@MainActor
final class BubbleWindow {
    private(set) var model = BubbleContent()
    private let hover = BubbleHover()
    let panel: NSPanel
    private let host: NSHostingView<BubbleView>
    private var hideTask: Task<Void, Never>?
    private weak var anchor: NSWindow?

    init(anchor: NSWindow) {
        self.anchor = anchor
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        host = NSHostingView(rootView: BubbleView(model: BubbleContent(), hover: hover, onClose: {}))
        host.sizingOptions = []
        panel.contentView = host
    }

    // MARK: content

    /// A new turn: show what I said.
    func showYou(_ text: String) {
        hideTask?.cancel()
        model = BubbleContent(you: text)
        relayout()
    }

    /// A streamed sentence of the reply.
    func appendReply(_ sentence: String) {
        hideTask?.cancel()
        model.reply = model.reply.isEmpty ? sentence : model.reply + " " + sentence
        relayout()
    }

    /// The full reply (core's `bubble` message). `summarised`: only part was spoken; show it all as a card.
    func showFullReply(_ text: String, summarised: Bool) {
        model.reply = text
        model.card = summarised
        relayout()
    }

    /// The reply has been spoken: hide after a while (longer for a card, never while hovered).
    func replyDone() {
        let words = model.reply.split(separator: " ").count
        let secs = model.card ? 90.0 : max(6, Double(words) * 0.3)
        scheduleHide(after: secs)
    }

    func clear() { hide() }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
        model = BubbleContent(); hover.on = false
    }

    private func scheduleHide(after secs: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            var left = secs
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if self?.hover.on != true { left -= 1 }
            }
            self?.hide()
        }
    }

    // MARK: layout

    /// Above the character if there's room, else below; right-aligned with it, kept on screen.
    func relayout() {
        guard let a = anchor, !(model.you.isEmpty && model.reply.isEmpty) else { return }
        let view = BubbleView(model: model, hover: hover, onClose: { [weak self] in self?.hide() })
        let size = NSHostingView(rootView: view).fittingSize     // a fresh view measures synchronously
        host.rootView = view
        let screen = (a.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let af = a.frame
        var x = af.midX + 40 - size.width
        var y = af.maxY - 14
        if y + size.height > screen.maxY { y = af.minY + 14 - size.height }
        if af.midX < screen.midX { x = af.midX - 40 }          // character on the left: bubble to its right
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        y = min(max(y, screen.minY + 8), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
