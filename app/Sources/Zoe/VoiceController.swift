import AppKit
import ZoeKit

/// Glues the push-to-talk key, the audio engine, VAD and the turn machine together (#3).
/// The machine decides; this class performs its actions.
@MainActor
final class VoiceController {
    var onUIState: ((TurnMachine.UIState) -> Void)?
    /// Mic level while listening (0…1), on the main actor.
    var onMicLevel: ((Float) -> Void)?
    var onStatus: ((String) -> Void)?
    /// A finished turn: 16 kHz mono samples (before transcription).
    var onTurn: (([Float]) -> Void)?
    /// The transcript of a turn ("" if nothing was said) and how long Whisper took.
    var onTranscript: ((String, Double) -> Void)?
    let stt = WhisperSTT()
    let speaker = Speaker()
    /// Live caption of the current turn (Apple's on-device recogniser; for display only).
    let captions = LiveCaptions()
    var onCaption: ((String) -> Void)?
    private let captionsOn = ProcessInfo.processInfo.environment["ZOE_CAPTIONS"] != "0"
    /// The user talked over a reply (key or click): the app tells the core and drops the rest of it.
    var onInterrupt: (() -> Void)?
    /// Say "On it." if the reply hasn't started this long after the transcript went to the core.
    var ackDelay: Duration = .milliseconds(800)
    private var ackTask: Task<Void, Never>?
    // Per-turn latency metrics, printed as "[metrics]" lines (no transcript text).
    private var turnNo = 0
    private var turnEndAt: TimeInterval = 0
    private var firstSentence = true
    private func metric(_ what: String) {
        print(String(format: "[metrics] turn %d: end of turn → %@ %.0f ms", turnNo, what, (Self.now() - turnEndAt) * 1000))
    }
    // Voice approvals (#17): one card at a time, oldest first.
    private struct VoiceApproval { let id: String; let summary: String; let voiceOK: Bool; var retried = false }
    private var approvalQueue: [VoiceApproval] = []
    private var answering: (id: String, promptEnd: TimeInterval)?
    private var answerSpeechStart: TimeInterval?
    /// A spoken answer to an approval card: (pending id, approved).
    var onApprovalAnswer: ((String, Bool) -> Void)?
    private var unloadTask: Task<Void, Never>?
    /// Unload Whisper this long after a conversation ends (keeps ~185 MB out of the idle app).
    var unloadAfter: Duration = .seconds(120)

    private var machine = TurnMachine()
    private let audio = AudioEngine()
    private var listener: Listener?
    private let hotkey: Hotkey
    private let calls = CallDetect()
    private var tickTimer: Timer?
    private var triggerAt: TimeInterval = 0

    init() {
        let kind = Hotkey.Kind(rawValue: ProcessInfo.processInfo.environment["ZOE_HOTKEY"] ?? "") ?? .rightOption
        hotkey = Hotkey(kind: kind)
    }

    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start() async {
        do {
            let vad = try SileroVAD(modelPath: try await ModelStore.path(for: .sileroVAD))
            let l = Listener(vad: vad)
            l.onSpeech = { e in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.answering != nil { self.answerSpeech(e); return }   // a yes/no, not a new turn
                    switch e {
                    case .start: self.handle(.speechStart(Self.now()))
                    case .end: self.handle(.speechEnd(Self.now()))
                    }
                }
            }
            l.onLevel = { v in Task { @MainActor [weak self] in self?.onMicLevel?(v) } }
            listener = l
            let c = captions
            audio.onSamples = { [weak l] s in l?.feed(s); c.feed(s) }
            captions.onText = { [weak self] t in self?.onCaption?(t) }
        } catch {
            onStatus?("Voice unavailable: \(error)")
            return
        }

        if hotkey.kind == .rightOption && !Hotkey.accessibilityTrusted {
            Hotkey.requestAccessibility()
            onStatus?("Grant Accessibility to use right ⌥; click the menu to talk meanwhile")
        }
        hotkey.onSignal = { sig in
            Task { @MainActor [weak self] in
                let t = Self.now()
                switch sig {
                case .down: self?.triggerAt = t; self?.handle(.keyDown(t))
                case .up: self?.handle(.keyUp(t))
                case .cancelled: self?.handle(.keyCancelled(t))
                }
            }
        }
        if !hotkey.start() { onStatus?("Push-to-talk key unavailable (Accessibility?)") }

        calls.onChange = { inCall in
            Task { @MainActor [weak self] in self?.handle(inCall ? .callStarted : .callEnded) }
        }
        calls.start()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.handle(.tick(Self.now())) }
        }
        let key = hotkey.kind == .rightOption ? "right ⌥" : "⌃⌥Space"
        onStatus?("Hold \(key) to talk, or tap it for a conversation")
        speaker.onReplyDone = { [weak self] in self?.replyFinished() }
        speaker.onFirstAudio = { [weak self] in self?.metric("first reply audio") }
        let warm = await speaker.warmUp()
        print(String(format: "voice: %@ (%@), warmed up in %.0f ms", speaker.voice.name, speaker.voice.identifier, warm))
        prepareSpeechModelIfNeeded()
    }

    /// The first load compiles Whisper for the Neural Engine (minutes). Do it now, in the background,
    /// rather than in the first conversation; a turn that arrives meanwhile waits for the same load.
    private func prepareSpeechModelIfNeeded() {
        Task { [stt, weak self] in
            guard await !stt.isPrepared else { return }
            await MainActor.run { self?.onStatus?("Preparing the speech model (one time, a few minutes)…") }
            do {
                let t0 = Date()
                try await stt.load()          // may join a load a conversation already started
                let ms = Date().timeIntervalSince(t0) * 1000
                await MainActor.run {
                    guard let self else { return }
                    self.onStatus?(String(format: "Speech model ready (prepared in %.0f s)", ms / 1000))
                    if !self.audio.isRunning { Task { await self.stt.unload() } }
                }
            } catch {
                await MainActor.run { self?.onStatus?("Speech model unavailable: \(error)") }
            }
        }
    }

    /// Click on the character or the menu item.
    func click() { triggerAt = Self.now(); handle(.click(triggerAt)) }

    /// The reply has been spoken (or shown); in a hands-free conversation Zoe listens again.
    func replyFinished() { ackTask?.cancel(); onReplyDone?(); handle(.replyFinished(Self.now())) }
    /// The reply has been spoken (or there was nothing to say).
    var onReplyDone: (() -> Void)?

    /// A sentence of the reply, as it streams from the core.
    func speak(_ text: String) {
        ackTask?.cancel()
        if firstSentence { firstSentence = false; metric("first reply sentence") }
        speaker.enqueue(text)
    }

    /// The reply's last chunk arrived; the turn ends once it has been spoken.
    func endReply() {
        ackTask?.cancel()
        speaker.endReply()
    }

    /// The transcript went to the core: if the reply is slow to start, acknowledge it.
    func turnSent() {
        ackTask?.cancel()
        ackTask = Task { [weak self, ackDelay] in
            try? await Task.sleep(for: ackDelay)
            guard !Task.isCancelled, let self, !self.speaker.isSpeaking else { return }
            self.speaker.playAcknowledgement()
            self.metric("acknowledgement (\"On it.\")")
        }
    }

    func endConversation() { handle(.endConversationRequested(Self.now())) }

    // MARK: voice approvals (#17)

    /// The core asked for approval. Zoe speaks the card's summary; if voice is allowed and the mic is on, it then
    /// listens for one answer that starts after the prompt has finished.
    func approvalAsked(id: String, summary: String, voiceOK: Bool) {
        guard !approvalQueue.contains(where: { $0.id == id }) else { return }
        approvalQueue.append(VoiceApproval(id: id, summary: summary, voiceOK: voiceOK))
        if approvalQueue.count == 1 { promptNext() }
    }

    /// Answered by click, timed out, withdrawn, or answered by voice: forget it and move to the next one.
    func approvalClosed(id: String) {
        let wasFirst = approvalQueue.first?.id == id
        approvalQueue.removeAll { $0.id == id }
        if answering?.id == id { stopAnswering() }
        if wasFirst { promptNext() }
    }

    private var canListen: Bool { audio.isRunning && listener != nil }

    private func promptNext() {
        guard let a = approvalQueue.first else { return }
        let listen = a.voiceOK && canListen
        let tail = !a.voiceOK ? "This one needs a click." : listen ? "Say yes or no." : "Approve it on screen."
        speaker.enqueue("\(a.summary) \(tail)", onPlayed: { [weak self] in
            guard let self, listen, self.approvalQueue.first?.id == a.id else { return }
            self.startAnswering(a.id)
        })
    }

    private func startAnswering(_ id: String) {
        answering = (id, Self.now())
        answerSpeechStart = nil
        audio.samplesQueue.async { [listener] in listener?.begin() }       // nothing heard before this counts
        onUIState?(.listening)
    }

    private func stopAnswering() {
        answering = nil
        answerSpeechStart = nil
        audio.samplesQueue.async { [listener] in listener?.pause() }
        if machine.phase != .idle { onUIState?(.thinking) }
    }

    private func answerSpeech(_ e: SpeechSegmenter.Event) {
        guard let (id, promptEnd) = answering else { return }
        switch e {
        case .start:
            answerSpeechStart = Self.now()
        case .end:
            let started = answerSpeechStart ?? 0
            audio.samplesQueue.async { [listener, weak self] in
                guard let samples = listener?.takeTurn() else { return }
                listener?.pause()
                Task { @MainActor in
                    guard let self, self.answering?.id == id else { return }
                    let text = (try? await self.stt.transcribe(samples))?.text ?? ""
                    let answer = VoiceAnswer.accepted(speechStart: started, promptEnd: promptEnd) ? VoiceAnswer.classify(text) : .unclear
                    print("[metrics] approval answer by voice: \(answer)")
                    switch answer {
                    case .yes, .no:
                        self.answering = nil
                        self.onApprovalAnswer?(id, answer == .yes)
                    case .unclear:
                        if let i = self.approvalQueue.firstIndex(where: { $0.id == id }), !self.approvalQueue[i].retried {
                            self.approvalQueue[i].retried = true
                            self.answering = nil
                            self.speaker.enqueue("Sorry, was that a yes or a no?", onPlayed: { [weak self] in
                                guard let self, self.approvalQueue.first?.id == id else { return }
                                self.startAnswering(id)
                            })
                        } else {
                            self.stopAnswering()
                            self.speaker.enqueue("I'll wait for a click.")
                        }
                    }
                }
            }
        }
    }

    private func handle(_ e: TurnMachine.Event) {
        for action in machine.handle(e) { perform(action) }
    }

    private func perform(_ a: TurnMachine.Action) {
        switch a {
        case .chime(let c):
            NSSound(named: c == .start ? "Tink" : "Pop")?.play()
        case .startEngine:
            unloadTask?.cancel()
            Task { [stt, weak self] in        // load Whisper while I'm still speaking
                do {
                    let wasLoaded = await stt.isLoaded
                    try await stt.load { p in Task { @MainActor in self?.onStatus?(String(format: "Downloading the speech model… %.0f %%", p * 100)) } }
                    if !wasLoaded { let ms = await stt.lastLoadMillis; await MainActor.run { self?.onStatus?(String(format: "speech model loaded in %.0f ms", ms)) } }
                }
                catch { await MainActor.run { self?.onStatus?("Speech model unavailable: \(error)") } }
            }
            do {
                try audio.start(voiceProcessing: ProcessInfo.processInfo.environment["ZOE_VP"] == "1")
                audio.samplesQueue.async { [listener] in listener?.begin() }
                let ms = (Self.now() - triggerAt) * 1000
                onStatus?(String(format: "Listening (trigger → engine running %.0f ms; engine start %.0f ms)", ms, audio.lastStartMillis))
            } catch {
                onStatus?("Couldn't start the microphone: \(error.localizedDescription)")
                handle(.endConversationRequested(Self.now()))
            }
        case .stopEngine:
            captions.end()
            audio.stop()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.machine.phase == .idle else { return }   // a new conversation already started
                print("[metrics] conversation ended; mic held: \(CallDetect.selfCapturing())")
            }
            audio.samplesQueue.async { [listener] in listener?.pause() }
            unloadTask?.cancel()
            unloadTask = Task { [stt, unloadAfter] in
                try? await Task.sleep(for: unloadAfter)
                if !Task.isCancelled { await stt.unload() }
            }
        case .endTurn:
            captions.end()
            turnNo += 1; turnEndAt = Self.now(); firstSentence = true
            audio.samplesQueue.async { [listener, weak self] in
                guard let samples = listener?.takeTurn() else { return }
                listener?.pause()      // half-duplex until the reply is done (barge-in comes with #5)
                Task { @MainActor in
                    guard let self else { return }
                    self.onTurn?(samples)
                    do {
                        let r = try await self.stt.transcribe(samples)
                        self.metric(String(format: "transcript (Whisper %.0f ms, %.1f s of audio)", r.millis, Double(samples.count) / 16000))
                        self.onTranscript?(r.text, r.millis)
                        if r.text.isEmpty { self.replyFinished() }   // nothing said: keep listening
                    } catch {
                        self.onStatus?("Couldn't transcribe: \(error.localizedDescription)")
                        self.replyFinished()
                    }
                }
            }
        case .discardTurn:
            audio.samplesQueue.async { [listener] in listener?.clear() }
            if machine.phase != .idle, captionsOn { captions.begin() }   // a fresh caption for the next turn
        case .setState(let s):
            if s == .listening {
                audio.samplesQueue.async { [listener] in listener?.resume() }
                if captionsOn { captions.begin() }
            }
            onUIState?(s)
        case .interruptReply:
            ackTask?.cancel()
            speaker.stop()
            onInterrupt?()
        case .refuse(let why):
            NSSound.beep()
            onStatus?("Not now: \(why)")
        }
    }
}
