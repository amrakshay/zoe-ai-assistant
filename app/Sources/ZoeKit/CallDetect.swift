import CoreAudio
import Foundation

/// Is another app capturing the mic (a call)? Per-process CoreAudio objects, no permission needed (F07).
/// Polled every few seconds (~1 ms each); Zoe's own process is ignored.
public final class CallDetect: @unchecked Sendable {
    public var onChange: (@Sendable (Bool) -> Void)?
    public private(set) var inCall = false
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "zoe.calldetect")
    private let interval: TimeInterval

    public init(interval: TimeInterval = 3) { self.interval = interval }

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    public func stop() { timer?.cancel(); timer = nil }

    private func poll() {
        let now = Self.otherProcessCapturing()
        if now != inCall { inCall = now; onChange?(now) }
    }

    /// PIDs (other than ours) currently running audio input.
    public static func capturingPIDs() -> [pid_t] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let me = getpid()
        return ids.compactMap { o in
            let pid: pid_t = prop(o, kAudioProcessPropertyPID, -1)
            let input: UInt32 = prop(o, kAudioProcessPropertyIsRunningInput, 0)
            return (input != 0 && pid != me && pid > 0) ? pid : nil
        }
    }

    public static func otherProcessCapturing() -> Bool { !capturingPIDs().isEmpty }

    /// Whether *this* process is running audio input (the mic is held). Used to check it's released.
    public static func selfCapturing() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return false }
        return ids.contains { o in
            let pid: pid_t = prop(o, kAudioProcessPropertyPID, -1)
            let input: UInt32 = prop(o, kAudioProcessPropertyIsRunningInput, 0)
            return pid == getpid() && input != 0
        }
    }

    private static func prop<T: BitwiseCopyable>(_ o: AudioObjectID, _ sel: AudioObjectPropertySelector, _ def: T) -> T {
        var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var v = def
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(o, &addr, 0, nil, &size, &v) == noErr ? v : def
    }
}
