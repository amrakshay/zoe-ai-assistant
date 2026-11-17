import AppKit
import ZoeKit

/// Glues the push-to-talk key, the audio engine, VAD and the turn machine together (#3).
/// The machine decides; this class performs its actions.
@MainActor
final class VoiceController {
    var onUIState: ((TurnMachine.UIState) -> Void)?
    var onStatus: ((String) -> Void)?
    /// A finished turn: 16 kHz mono samples (before transcription).
    var onTurn: (([Float]) -> Void)?
    /// The transcript of a turn ("" if nothing was said) and how long Whisper took.
    var onTranscript: ((String, Double) -> Void)?
    let stt = WhisperSTT()
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
                    switch e {
                    case .start: self?.handle(.speechStart(Self.now()))
                    case .end: self?.handle(.speechEnd(Self.now()))
                    }
                }
            }
            listener = l
            audio.onSamples = { [weak l] s in l?.feed(s) }
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
        onStatus?("Hold right ⌥ to talk, or tap it for a conversation")
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
    func replyFinished() { handle(.replyFinished(Self.now())) }

    func endConversation() { handle(.endConversationRequested(Self.now())) }

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
            audio.stop()
            audio.samplesQueue.async { [listener] in listener?.pause() }
            unloadTask?.cancel()
            unloadTask = Task { [stt, unloadAfter] in
                try? await Task.sleep(for: unloadAfter)
                if !Task.isCancelled { await stt.unload() }
            }
        case .endTurn:
            audio.samplesQueue.async { [listener, weak self] in
                guard let samples = listener?.takeTurn() else { return }
                listener?.pause()      // half-duplex until the reply is done (barge-in comes with #5)
                Task { @MainActor in
                    guard let self else { return }
                    self.onTurn?(samples)
                    do {
                        let r = try await self.stt.transcribe(samples)
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
        case .setState(let s):
            if s == .listening { audio.samplesQueue.async { [listener] in listener?.resume() } }
            onUIState?(s)
        case .refuse(let why):
            NSSound.beep()
            onStatus?("Not now: \(why)")
        }
    }
}
