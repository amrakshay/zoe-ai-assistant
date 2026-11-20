import AppKit
import SwiftUI

/// What the bubble shows (#6): what I said, then Zoe's reply as it streams. A long (summarised) reply
/// opens as a scrollable card with the full text (PLAN.md §5.12).
/// A plain value, so the panel can be measured synchronously from a fresh view.
struct BubbleContent: Equatable {
    var place = ""            // the session's repo or folder when it isn't home (#30)
    var you = ""
    var reply = ""
    var card = false          // full reply in a scrollable card
    var approvals: [ApprovalCard] = []   // waiting for my answer, oldest first; the first is shown
    var questions: [QuestionCard] = []   // Claude's questions (#19), after any approvals
    var terminals: [TerminalCard] = []   // things to run in Terminal myself (#19)
    var typing = false                   // the "Type to Zoe" box is open (#37)

    var isEmpty: Bool { you.isEmpty && reply.isEmpty && waiting == 0 && !typing }
    var waiting: Int { approvals.count + questions.count + terminals.count }
}

/// Something only a terminal can answer (#19): a password prompt, an interactive login, a connector sign-in.
struct TerminalCard: Equatable {
    var id: String, title: String, command: String, cwd: String, note: String

    init?(message m: [String: Any]) {
        guard let id = m["id"] as? String, let c = m["card"] as? [String: Any], let cmd = c["command"] as? String else { return nil }
        self.id = id; command = cmd
        title = c["title"] as? String ?? "Run this in Terminal"
        cwd = c["cwd"] as? String ?? ""
        note = c["note"] as? String ?? ""
    }
}

/// Claude's AskUserQuestion (#19): 1–4 questions with 2–4 options each, answered one at a time.
struct QuestionCard: Equatable {
    struct Option: Equatable { var label: String; var detail: String }
    struct Question: Equatable { var text: String; var header: String; var options: [Option]; var multi: Bool }
    var id: String
    var questions: [Question]

    init?(message m: [String: Any]) {
        guard let id = m["id"] as? String, let qs = m["questions"] as? [[String: Any]] else { return nil }
        self.id = id
        questions = qs.compactMap { q in
            guard let text = q["question"] as? String else { return nil }
            let opts = (q["options"] as? [[String: Any]] ?? []).map {
                Option(label: $0["label"] as? String ?? "", detail: $0["description"] as? String ?? "")
            }
            return Question(text: text, header: q["header"] as? String ?? "", options: opts, multi: q["multiSelect"] as? Bool ?? false)
        }
        if questions.isEmpty { return nil }
    }
}

/// Where I am in the current question card: kept outside the measured value so typing doesn't relayout.
@MainActor @Observable
final class QuestionState {
    var index = 0
    var selected: Set<String> = []
    var typing = false
    var typed = ""
    var answers: [String: String] = [:]
    func reset() { index = 0; selected = []; typing = false; typed = ""; answers = [:] }
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
    /// A command card's "run it in Terminal myself" target (#22 feedback).
    var terminal: (command: String, cwd: String)?

    static func == (a: ApprovalCard, b: ApprovalCard) -> Bool {
        a.id == b.id && a.title == b.title && a.fields == b.fields && a.why == b.why && a.voiceOK == b.voiceOK
            && a.terminal?.command == b.terminal?.command && a.terminal?.cwd == b.terminal?.cwd
    }

    init?(message m: [String: Any]) {
        guard let id = m["id"] as? String, let card = m["card"] as? [String: Any] else { return nil }
        self.id = id
        if let t = card["terminal"] as? [String: Any], let c = t["command"] as? String {
            terminal = (c, t["cwd"] as? String ?? "")
        }
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

/// What I'm typing (#37): outside the measured value, so typing doesn't relayout the panel.
@MainActor @Observable
final class TypingState { var text = "" }

/// The text box, focused as soon as it appears.
struct TypingField: View {
    let state: TypingState
    var onSend: () -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Type to Zoe…", text: Binding(get: { state.text }, set: { state.text = $0 }))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(onSend)
                .onExitCommand(perform: onCancel)
            Button("Send", action: onSend).disabled(state.text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { focused = true }
    }
}

struct BubbleView: View {
    let model: BubbleContent
    let hover: BubbleHover
    /// The bubble's width (text wraps to it); nil measures the text's natural one-line width.
    var width: CGFloat? = nil
    var onClose: () -> Void
    var onAnswer: (String, Bool) -> Void = { _, _ in }
    var qs: QuestionState? = nil
    var onQuestion: (QuestionAction) -> Void = { _ in }
    var onTerminal: (String, Bool) -> Void = { _, _ in }      // (id, open)
    var onHandOff: () -> Void = {}                             // the way out: the whole conversation in Terminal
    var onRunInTerminal: (String) -> Void = { _ in }           // a command card: run it in Terminal myself
    var typingState: TypingState? = nil
    var onTypedSend: () -> Void = {}
    var onTypedCancel: () -> Void = {}

    enum QuestionAction { case choose(String), toggle(String), done, other, send }

    static let maxWidth: CGFloat = 380
    static let cardHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.place.isEmpty && !(model.you.isEmpty && model.reply.isEmpty) {
                Label("in \(model.place)", systemImage: "folder").font(.caption).foregroundStyle(.secondary)
            }
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
            if model.typing, let typingState {
                TypingField(state: typingState, onSend: onTypedSend, onCancel: onTypedCancel)
            }
            if let a = model.approvals.first {
                if !model.you.isEmpty || !model.reply.isEmpty { Divider().padding(.vertical, 2) }
                approval(a, more: model.waiting - 1)
            } else if let q = model.questions.first, let qs {
                if !model.you.isEmpty || !model.reply.isEmpty { Divider().padding(.vertical, 2) }
                question(q, state: qs, more: model.waiting - 1)
            } else if let t = model.terminals.first {
                if !model.you.isEmpty || !model.reply.isEmpty { Divider().padding(.vertical, 2) }
                terminal(t, more: model.waiting - 1)
            }
        }
        .font(.body)
        .padding(12)
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: width == nil, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hover.on && model.waiting == 0 {   // something waiting for me can't be closed away
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
                if a.terminal != nil {
                    Button { onRunInTerminal(a.id) } label: { Label("Run in Terminal", systemImage: "terminal") }
                        .help("Run this exact command in Terminal yourself; Zoe won't run it")
                } else {
                    Button { onHandOff() } label: { Image(systemName: "terminal") }.help("Open this conversation in Terminal instead")
                }
                Button("Deny") { onAnswer(a.id, false) }
                Button("Approve") { onAnswer(a.id, true) }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func question(_ card: QuestionCard, state: QuestionState, more: Int) -> some View {
        let q = card.questions[min(state.index, card.questions.count - 1)]
        VStack(alignment: .leading, spacing: 6) {
            Label(q.header.isEmpty ? "Question" : q.header, systemImage: "questionmark.bubble.fill")
                .font(.caption).foregroundStyle(.blue)
            Text(q.text).font(.headline).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.options.enumerated()), id: \.offset) { _, o in
                Button { onQuestion(q.multi ? .toggle(o.label) : .choose(o.label)) } label: {
                    HStack(alignment: .top) {
                        if q.multi { Image(systemName: state.selected.contains(o.label) ? "checkmark.square.fill" : "square") }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o.label)
                            if !o.detail.isEmpty { Text(o.detail).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            if state.typing {
                HStack {
                    TextField("Your answer", text: Binding(get: { state.typed }, set: { state.typed = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { onQuestion(.send) }
                    Button("Send") { onQuestion(.send) }.disabled(state.typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            HStack {
                if card.questions.count > 1 { Text("\(state.index + 1) of \(card.questions.count)").font(.caption).foregroundStyle(.secondary) }
                if more > 0 { Text("+\(more) more waiting").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { onHandOff() } label: { Image(systemName: "terminal") }.help("Open this conversation in Terminal instead")
                if !state.typing { Button("Other…") { onQuestion(.other) } }
                if q.multi { Button("Done") { onQuestion(.done) }.disabled(state.selected.isEmpty) }
            }
        }
    }

    @ViewBuilder
    private func terminal(_ t: TerminalCard, more: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(t.title, systemImage: "terminal.fill").font(.headline).foregroundStyle(.purple)
            if !t.note.isEmpty { Text(t.note).font(.callout).fixedSize(horizontal: false, vertical: true) }
            Text(t.command).font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
            if !t.cwd.isEmpty { Text("in \(t.cwd)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            HStack {
                if more > 0 { Text("+\(more) more waiting").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Dismiss") { onTerminal(t.id, false) }
                Button("Open in Terminal") { onTerminal(t.id, true) }.buttonStyle(.borderedProminent)
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
    private(set) var model = BubbleContent() {
        didSet { if model.waiting != oldValue.waiting { onWaitingChanged?(model.waiting) } }
    }
    /// The number of cards waiting for me changed (for the character's badge, #21).
    var onWaitingChanged: ((Int) -> Void)?
    var isVisible: Bool { panel.isVisible }
    private let hover = BubbleHover()
    let panel: NSPanel
    private let host: NSHostingView<BubbleView>
    private let qs = QuestionState()
    /// My answers to a question card: (pending id, {question text: label(s) joined, or typed text}).
    var onQuestionAnswered: ((String, [String: String]) -> Void)?
    /// A terminal card was opened or dismissed: (card, opened).
    var onTerminalDone: ((TerminalCard, Bool) -> Void)?
    /// A card's way out: open the whole conversation in Terminal (#20).
    var onHandOff: (() -> Void)?
    /// A command card's "Run in Terminal": (card).
    var onRunInTerminal: ((ApprovalCard) -> Void)?
    /// A typed request (#37).
    var onTyped: ((String) -> Void)?
    private let typingState = TypingState()

    /// Opens the "Type to Zoe" box and takes keystrokes (without activating the app).
    func openTyping() {
        hideTask?.cancel()
        model.typing = true
        relayout()
        panel.makeKey()
    }

    func closeTyping() {
        model.typing = false
        typingState.text = ""
        if model.isEmpty { hide() } else { relayout() }
    }

    func showTerminal(_ t: TerminalCard) {
        hideTask?.cancel()
        if !model.terminals.contains(where: { $0.id == t.id }) { model.terminals.append(t) }
        relayout()
    }

    func removeTerminal(_ id: String) {
        model.terminals.removeAll { $0.id == id }
        if model.isEmpty { hide() } else { relayout(); if model.waiting == 0 { replyDone() } }
    }
    private var hideTask: Task<Void, Never>?
    private weak var anchor: NSWindow?
    /// My answer to an approval card: (pending id, approved).
    var onAnswer: ((String, Bool) -> Void)?

    init(anchor: NSWindow) {
        self.anchor = anchor
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
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
        model = BubbleContent(place: model.place, you: text, approvals: model.approvals, questions: model.questions, terminals: model.terminals)
        relayout()
    }

    /// Where Zoe is working (#30): a repo or folder name, or "" for home.
    func setPlace(_ name: String) {
        model.place = name
        if !model.isEmpty { relayout() }
    }

    /// Live caption while I speak (replaced by Whisper's transcript when the turn ends).
    func showCaption(_ text: String) {
        hideTask?.cancel()
        model = BubbleContent(place: model.place, you: text, approvals: model.approvals, questions: model.questions, terminals: model.terminals)
        relayout()
    }

    /// A question from Claude (#19), shown after any waiting approvals.
    func showQuestion(_ q: QuestionCard) {
        hideTask?.cancel()
        if model.questions.isEmpty { qs.reset() }
        if !model.questions.contains(where: { $0.id == q.id }) { model.questions.append(q) }
        relayout()
    }

    private func questionAction(_ a: BubbleView.QuestionAction) {
        guard let card = model.questions.first else { return }
        let q = card.questions[min(qs.index, card.questions.count - 1)]
        func record(_ value: String) {
            qs.answers[q.text] = value
            qs.selected = []; qs.typing = false; qs.typed = ""
            if qs.index + 1 < card.questions.count { qs.index += 1; relayout() }
            else { let answers = qs.answers; onQuestionAnswered?(card.id, answers); removeQuestion(card.id) }
        }
        switch a {
        case .choose(let l): record(l)
        case .toggle(let l): if qs.selected.contains(l) { qs.selected.remove(l) } else { qs.selected.insert(l) }; relayout()
        case .done: record(q.options.map(\.label).filter(qs.selected.contains).joined(separator: ", "))
        case .other: qs.typing = true; relayout(); panel.makeKey()
        case .send:
            let t = qs.typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { record(t) }
        }
    }

    func removeQuestion(_ id: String) {
        let wasFirst = model.questions.first?.id == id
        model.questions.removeAll { $0.id == id }
        if wasFirst { qs.reset() }
        if model.isEmpty { hide() } else { relayout(); if model.waiting == 0 { replyDone() } }
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
        if model.isEmpty { hide() } else { relayout(); if model.waiting == 0 { replyDone() } }
    }

    var waiting: Int { model.waiting }

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
        guard model.waiting == 0 else { return }     // stays until everything waiting is answered
        let words = model.reply.split(separator: " ").count
        let secs = model.card ? 90.0 : max(6, Double(words) * 0.3)
        scheduleHide(after: secs)
    }

    func clear() { hide() }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
        model = BubbleContent(place: model.place); hover.on = false
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
        let qa: (BubbleView.QuestionAction) -> Void = { [weak self] a in self?.questionAction(a) }
        let term: (String, Bool) -> Void = { [weak self] id, open in
            guard let self, let t = self.model.terminals.first(where: { $0.id == id }) else { return }
            self.removeTerminal(id)
            self.onTerminalDone?(t, open)
        }
        func view(_ w: CGFloat?) -> BubbleView {
            BubbleView(model: shown, hover: hover, width: w, onClose: close, onAnswer: answer, qs: qs, onQuestion: qa,
                       onTerminal: term, onHandOff: { [weak self] in self?.onHandOff?() },
                       onRunInTerminal: { [weak self] id in
                           guard let self, let a = self.model.approvals.first(where: { $0.id == id }) else { return }
                           self.onRunInTerminal?(a)
                       },
                       typingState: typingState,
                       onTypedSend: { [weak self] in
                           guard let self else { return }
                           let t = self.typingState.text.trimmingCharacters(in: .whitespacesAndNewlines)
                           guard !t.isEmpty else { return }
                           self.closeTyping()
                           self.onTyped?(t)
                       },
                       onTypedCancel: { [weak self] in self?.closeTyping() })
        }
        func measure(_ w: CGFloat?) -> NSSize { NSHostingView(rootView: view(w)).fittingSize }
        let pad: CGFloat = 6 * 2          // the outer padding; `width` includes the inner one
        var width = shown.card || shown.waiting > 0 || shown.typing ? BubbleView.maxWidth : min(measure(nil).width - pad, BubbleView.maxWidth)
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

/// A borderless panel can't normally take keystrokes; this one can, without activating the app (for typing an
/// answer to Claude's question, #19).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
