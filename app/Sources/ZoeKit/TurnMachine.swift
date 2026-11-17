import Foundation

/// Decides when Zoe listens, when a turn ends and when the conversation is over (PLAN.md §3, rev 7).
/// Pure logic: the app feeds it events with timestamps and performs the actions it returns.
///
/// - **Hold** the hotkey: listen while held; release ends the turn. One turn, then the conversation ends.
/// - **Tap** the hotkey or **click**: a hands-free conversation. VAD ends each turn; the mic stays open
///   for follow-ups until ~20 s of silence, "bye" (the core decides), a click, or another tap.
/// - Holding the key during a hands-free conversation is a push-to-talk turn inside it.
/// - A call stops everything, and triggers are refused while it lasts.
public struct TurnMachine: Sendable {
    public enum Mode: Sendable, Equatable { case hold, handsFree }

    public enum Phase: Sendable, Equatable {
        case idle
        case listening(Mode)
        case waiting(Mode)      // turn sent; waiting for the reply to finish
    }

    public enum Event: Sendable, Equatable {
        case keyDown(TimeInterval)
        case keyUp(TimeInterval)
        case keyCancelled(TimeInterval)    // the key was used as a modifier (another key pressed)
        case click(TimeInterval)
        case speechStart(TimeInterval)
        case speechEnd(TimeInterval)       // VAD: enough silence after speech
        case replyFinished(TimeInterval)
        case endConversationRequested(TimeInterval)  // e.g. "bye", or the core says so
        case tick(TimeInterval)
        case callStarted
        case callEnded
    }

    public enum Action: Sendable, Equatable {
        case startEngine        // and start capturing (with the pre-roll since the trigger)
        case stopEngine         // release the mic
        case chime(Chime)
        case endTurn            // the captured audio is a turn: transcribe and send it
        case discardTurn        // nothing was said
        case setState(UIState)
        case refuse(String)     // e.g. "in a call"
        case interruptReply     // stop speaking and tell the core (a key press or click during a reply)
    }

    public enum Chime: Sendable, Equatable { case start, end }
    public enum UIState: Sendable, Equatable { case idle, listening, thinking, inCall }

    /// A press shorter than this is a tap.
    public var tapThreshold: TimeInterval = 0.35
    /// Hands-free: end the conversation after this long without speech.
    public var silenceTimeout: TimeInterval = 20

    public private(set) var phase: Phase = .idle
    public private(set) var inCall = false
    private var keyDownAt: TimeInterval?
    private var keyDownPhase: Phase = .idle
    private var heardSpeech = false
    private var lastActivity: TimeInterval = 0

    public init() {}

    public mutating func handle(_ e: Event) -> [Action] {
        switch e {
        case .callStarted:
            inCall = true
            let was = phase
            phase = .idle; keyDownAt = nil
            return (was == .idle ? [] : [.discardTurn, .stopEngine]) + [.setState(.inCall)]
        case .callEnded:
            inCall = false
            return [.setState(.idle)]
        default:
            break
        }
        if inCall {
            if case .keyDown = e { return [.refuse("in a call")] }
            if case .click = e { return [.refuse("in a call")] }
            return []
        }

        switch (phase, e) {
        // --- starting ---
        case (.idle, .keyDown(let t)):
            keyDownAt = t; keyDownPhase = .idle
            return begin(.hold, at: t)       // listen at once; tap vs hold is decided on release
        case (.idle, .click(let t)):
            return begin(.handsFree, at: t)

        // --- key released: four cases (started from idle or inside a conversation) × (tap or hold) ---
        case (.listening(.hold), .keyUp(let t)):
            guard let down = keyDownAt else { return [] }
            keyDownAt = nil
            let tap = t - down < tapThreshold
            let fromConversation = keyDownPhase != .idle
            let overReply = keyDownPhase == .waiting(.handsFree)
            keyDownPhase = .idle
            if overReply && tap {                     // a tap that only stopped the reply: keep listening
                phase = .listening(.handsFree); lastActivity = t
                return [.discardTurn]
            }
            switch (fromConversation, tap) {
            case (false, true):                       // tap from idle: hands-free conversation
                phase = .listening(.handsFree); lastActivity = t
                return []
            case (false, false):                      // held from idle: one push-to-talk turn
                return heardSpeech ? sendTurn(then: .hold, at: t) : endConversation(at: t)
            case (true, true):                        // tap during a conversation: end it
                return endConversation(at: t)
            case (true, false):                       // held during a conversation: a turn inside it
                if heardSpeech { return sendTurn(then: .handsFree, at: t) }
                phase = .listening(.handsFree); lastActivity = t
                return [.discardTurn]
            }
        case (.listening(.handsFree), .keyDown(let t)):
            keyDownAt = t; keyDownPhase = phase
            phase = .listening(.hold)                 // maybe push-to-talk inside the conversation
            heardSpeech = false
            return []
        case (.waiting(let mode), .keyDown(let t)):   // talking over a reply: stop it and listen
            keyDownAt = t
            keyDownPhase = mode == .handsFree ? .waiting(.handsFree) : .idle
            phase = .listening(.hold); heardSpeech = false; lastActivity = t
            return [.interruptReply, .setState(.listening)]
        case (.listening(.hold), .keyCancelled(let t)):
            keyDownAt = nil
            let fromConversation = keyDownPhase != .idle
            keyDownPhase = .idle
            if fromConversation { phase = .listening(.handsFree); lastActivity = t; return [.discardTurn] }
            return endConversation(at: t)
        case (.listening(.hold), .click(let t)):
            return endConversation(at: t)

        // --- hands-free ---
        case (.listening(.handsFree), .speechStart(let t)), (.listening(.hold), .speechStart(let t)):
            heardSpeech = true; lastActivity = t
            return []
        case (.listening(.handsFree), .speechEnd(let t)):
            return heardSpeech ? sendTurn(then: .handsFree, at: t) : []
        case (.listening(.handsFree), .click(let t)), (.waiting(_), .click(let t)):
            return endConversation(at: t)
        case (.listening(.handsFree), .tick(let t)):
            return t - lastActivity >= silenceTimeout ? endConversation(at: t) : []

        // --- replies ---
        case (.waiting(.handsFree), .replyFinished(let t)):
            phase = .listening(.handsFree); heardSpeech = false; lastActivity = t
            return [.setState(.listening)]
        case (.waiting(.hold), .replyFinished(let t)):
            return endConversation(at: t, replyDone: true)

        case (_, .endConversationRequested(let t)) where phase != .idle:
            return endConversation(at: t)

        default:
            return []
        }
    }

    private mutating func begin(_ mode: Mode, at t: TimeInterval) -> [Action] {
        phase = .listening(mode); heardSpeech = false; lastActivity = t
        return [.chime(.start), .startEngine, .setState(.listening)]
    }

    private mutating func sendTurn(then mode: Mode, at t: TimeInterval) -> [Action] {
        phase = .waiting(mode); heardSpeech = false; lastActivity = t
        return [.endTurn, .setState(.thinking)]
    }

    private mutating func endConversation(at t: TimeInterval, replyDone: Bool = false) -> [Action] {
        let wasListening: Bool = { if case .listening = phase { return true }; return false }()
        let wasWaiting: Bool = { if case .waiting = phase { return !replyDone }; return false }()
        phase = .idle; keyDownAt = nil; keyDownPhase = .idle; heardSpeech = false
        return (wasListening ? [.discardTurn] : []) + (wasWaiting ? [.interruptReply] : [])
            + [.chime(.end), .stopEngine, .setState(.idle)]
    }
}
