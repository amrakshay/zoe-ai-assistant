import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Push-to-talk key (F07). Default: hold **right ⌥** alone, seen through a `CGEventTap` (needs
/// Accessibility). Alternative: **⌃⌥Space** via `RegisterEventHotKey`. Both report press and release.
/// If another key is pressed while right ⌥ is held (⌥ used as a modifier), the press is cancelled.
public final class Hotkey: @unchecked Sendable {
    public enum Kind: String, Sendable { case rightOption = "right-option", controlOptionSpace = "ctrl-opt-space" }
    public enum Signal: Sendable { case down, up, cancelled }

    public let kind: Kind
    public var onSignal: (@Sendable (Signal) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate var rightDown = false

    public init(kind: Kind) { self.kind = kind }

    public static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show the Accessibility prompt if Zoe isn't trusted yet.
    public static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt"  // kAXTrustedCheckOptionPrompt (a global var, not concurrency-safe)
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Returns false if the key can't be watched (no Accessibility for right ⌥).
    @discardableResult
    public func start() -> Bool {
        switch kind {
        case .rightOption: return startTap()
        case .controlOptionSpace: return startHotKey()
        }
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil; handlerRef = nil
    }

    private func startTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                        eventsOfInterest: CGEventMask(mask), callback: { _, type, event, ctx in
            let hk = Unmanaged<Hotkey>.fromOpaque(ctx!).takeUnretainedValue()
            hk.handle(type, event)
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged where event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_RightOption):
            let down = event.flags.contains(.maskAlternate) && (event.flags.rawValue & 0x40) != 0  // right-⌥ device bit
            if down != rightDown {
                rightDown = down
                onSignal?(down ? .down : .up)
            }
        case .keyDown where rightDown:
            rightDown = false
            onSignal?(.cancelled)
        default:
            break
        }
    }

    private func startHotKey() -> Bool {
        var spec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let me = Unmanaged.passUnretained(self).toOpaque()
        let st = InstallEventHandler(GetApplicationEventTarget(), { _, ev, ctx in
            let hk = Unmanaged<Hotkey>.fromOpaque(ctx!).takeUnretainedValue()
            hk.onSignal?(GetEventKind(ev) == UInt32(kEventHotKeyPressed) ? .down : .up)
            return noErr
        }, 2, &spec, me, &handlerRef)
        let r = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                                    EventHotKeyID(signature: OSType(0x5A4F4521), id: 1), GetApplicationEventTarget(), 0, &hotKeyRef)
        return st == noErr && r == noErr
    }
}
