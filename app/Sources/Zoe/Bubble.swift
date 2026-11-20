import AppKit
import SwiftUI

/// What the bubble shows (#6): what I said, then Zoe's reply as it streams. A long (summarised) reply
/// opens as a scrollable card with the full text (PLAN.md §5.12).
/// A plain value, so the panel can be measured synchronously from a fresh view.
struct BubbleContent: Equatable {
    var you = ""
    var reply = ""
    var card = false          // full reply in a scrollable card
    var approvals: [ApprovalCard] = []   // waiting for my answer, oldest first; the first is shown

    var isEmpty: Bool { you.isEmpty && reply.isEmpty && approvals.isEmpty }
}

/// An approval request from the core (#15). Rendered by the core from the tool's raw input (#16), so the
/// app only displays fields; it never interprets them.
struct ApprovalCard: Equatable {
    struct Field: Equatable { var label: String; var value: String; var mono: Bool }
    var id: String
    var title: String
    var fields: [Field]
    var why: String
    var voiceOK: Bool

    init?(message m: [String: Any]) {
        guard let id = m["id"] as? String, let card = m["card"] as? [String: Any] else { return nil }
        self.id = id
        title = card["title"] as? String ?? "Allow this?"
        fields = (card["fields"] as? [[String: Any]] ?? []).map {
            Field(label: $0["label"] as? String ?? "", value: $0["value"] as? String ?? "", mono: $0["mono"] as? Bool ?? false)
        }
        why = card["why"] as? String ?? ""
        voiceOK = m["voice_ok"] as? Bool ?? false
    }
}

@MainActor @Observable
final class BubbleHover { var on = false }

struct BubbleView: View {
    let model: BubbleContent
    let hover: BubbleHover
    /// The bubble's width (text wraps to it); nil measures the text's natural one-line width.
    var width: CGFloat? = nil
    var onClose: () -> Void
    var onAnswer: (String, Bool) -> Void = { _, _ in }

    static let maxWidth: CGFloat = 380
    static let cardHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.you.isEmpty {
                Text(model.you)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(model.card ? 2 : 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.reply.isEmpty {
                if model.card {
                    ScrollView {
                        Text(Self.markdown(model.reply))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: Self.cardHeight)   // a ScrollView doesn't report its content height
                } else {
                    Text(Self.markdown(model.reply))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let a = model.approvals.first {
                if !model.you.isEmpty || !model.reply.isEmpty { Divider().padding(.vertical, 2) }
                approval(a, more: model.approvals.count - 1)
            }
        }
        .font(.body)
        .padding(12)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: width == nil, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hover.on && model.approvals.isEmpty {   // a waiting approval can't be closed away
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).padding(5)
            }
        }
        .onHover { hover.on = $0 }
        .padding(6)   // room for the material's edge
    }

    @ViewBuilder
    private func approval(_ a: ApprovalCard, more: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(a.title, systemImage: "hand.raised.fill").font(.headline).foregroundStyle(.orange)
            ForEach(Array(a.fields.enumerated()), id: \.offset) { _, f in
                VStack(alignment: .leading, spacing: 1) {
                    if !f.label.isEmpty { Text(f.label).font(.caption).foregroundStyle(.secondary) }
                    Text(f.value)
                        .font(f.mono ? .system(.callout, design: .monospaced) : .callout)
                        .textSelection(.enabled)
                        .lineLimit(14)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !a.why.isEmpty { Text(a.why).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if more > 0 { Text("+\(more) more waiting").font(.caption).foregroundStyle(.secondary) }
                if !a.voiceOK { Text("Needs a click").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Deny") { onAnswer(a.id, false) }
                Button("Approve") { onAnswer(a.id, true) }.buttonStyle(.borderedProminent)
            }
        }
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
    /// My answer to an approval card: (pending id, approved).
    var onAnswer: ((String, Bool) -> Void)?

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
        model = BubbleContent(you: text, approvals: model.approvals)
        relayout()
    }

    /// Live caption while I speak (replaced by Whisper's transcript when the turn ends).
    func showCaption(_ text: String) {
        hideTask?.cancel()
        model = BubbleContent(you: text, approvals: model.approvals)
        relayout()
    }

    /// An approval waiting for me (#15): queued; the bubble stays up until it's answered or withdrawn.
    func showApproval(_ a: ApprovalCard) {
        hideTask?.cancel()
        if !model.approvals.contains(where: { $0.id == a.id }) { model.approvals.append(a) }
        relayout()
    }

    /// The approval was answered, timed out or withdrawn.
    func removeApproval(_ id: String) {
        model.approvals.removeAll { $0.id == id }
        if model.isEmpty { hide() } else { relayout(); if model.approvals.isEmpty { replyDone() } }
    }

    var waitingApprovals: Int { model.approvals.count }

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
        guard model.approvals.isEmpty else { return }     // stays until every approval is answered
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
        guard let a = anchor, !model.isEmpty else { return }
        // Measure with fresh views (they lay out synchronously): first the text's natural width, capped;
        // then the height when wrapped to that width. Too tall for a bubble → show it as a scrolling card.
        var shown = model
        let close: () -> Void = { [weak self] in self?.hide() }
        let answer: (String, Bool) -> Void = { [weak self] id, ok in self?.onAnswer?(id, ok) }
        func view(_ w: CGFloat?) -> BubbleView {
            BubbleView(model: shown, hover: hover, width: w, onClose: close, onAnswer: answer)
        }
        func measure(_ w: CGFloat?) -> NSSize { NSHostingView(rootView: view(w)).fittingSize }
        let pad: CGFloat = 6 * 2          // the outer padding; `width` includes the inner one
        var width = shown.card || !shown.approvals.isEmpty ? BubbleView.maxWidth : min(measure(nil).width - pad, BubbleView.maxWidth)
        var size = measure(width)
        if !shown.card && size.height > BubbleView.cardHeight + 80 {
            shown.card = true; width = BubbleView.maxWidth; size = measure(width)
        }
        host.rootView = view(width)
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
