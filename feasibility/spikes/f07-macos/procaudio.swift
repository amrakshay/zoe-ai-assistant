// F07 step 1: list processes capturing audio input via CoreAudio process objects (macOS 14.2+).
// Usage: procaudio [--loop N] [--listen SECONDS] [--bench N]
import Foundation
import CoreAudio
import AppKit
import AVFoundation

func getProp<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ def: T) -> (OSStatus, T) {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v = def; var size = UInt32(MemoryLayout<T>.size)
    let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v)
    return (st, v)
}

func processObjects() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func bundleID(_ obj: AudioObjectID) -> String {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var cf: Unmanaged<CFString>? = nil; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &cf)
    guard st == noErr, let s = cf?.takeRetainedValue() else { return "" }
    return s as String
}

func procName(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { return (String(cString: buf) as NSString).lastPathComponent }
    return "?"
}

struct Row { let obj: AudioObjectID; let pid: pid_t; let bundle: String; let inRun: Bool; let outRun: Bool; let running: Bool }

func snapshot(details: Bool = true) -> [Row] {
    processObjects().map { o in
        let pid = getProp(o, kAudioProcessPropertyPID, pid_t(-1)).1
        let inR = getProp(o, kAudioProcessPropertyIsRunningInput, UInt32(0)).1 != 0
        let outR = getProp(o, kAudioProcessPropertyIsRunningOutput, UInt32(0)).1 != 0
        let r = getProp(o, kAudioProcessPropertyIsRunning, UInt32(0)).1 != 0
        return Row(obj: o, pid: pid, bundle: details ? bundleID(o) : "", inRun: inR, outRun: outR, running: r)
    }
}

let me = getpid()
func report() {
    let rows = snapshot()
    let capturing = rows.filter { $0.inRun }
    print("[\(ISO8601DateFormatter().string(from: Date()))] process objects: \(rows.count); capturing input: \(capturing.count)")
    for r in capturing {
        print("  INPUT pid=\(r.pid) name=\(procName(r.pid)) bundle=\(r.bundle.isEmpty ? "-" : r.bundle) self=\(r.pid == me)")
    }
    let others = capturing.filter { $0.pid != me }
    print("  => another process capturing: \(!others.isEmpty)")
}

let args = CommandLine.arguments
// --selfmic: this process also captures the mic, to prove self vs other separation
var selfEngine: AVAudioEngine? = nil
if args.contains("--selfmic") {
    let e = AVAudioEngine(); let inp = e.inputNode
    inp.installTap(onBus: 0, bufferSize: 1024, format: inp.outputFormat(forBus: 0)) { _, _ in }
    do { try e.start(); selfEngine = e; print("self capture started pid=\(me)") } catch { print("self capture failed: \(error)") }
    Thread.sleep(forTimeInterval: 1)
}
if let i = args.firstIndex(of: "--bench"), i+1 < args.count, let n = Int(args[i+1]) {
    // Cost of one poll: list + PID + IsRunningInput for every process object (no bundle lookup)
    _ = snapshot(details: false)
    let t0 = DispatchTime.now().uptimeNanoseconds
    var c = 0
    for _ in 0..<n { c += snapshot(details: false).filter { $0.inRun }.count }
    let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
    let ru = UnsafeMutablePointer<rusage>.allocate(capacity: 1); getrusage(RUSAGE_SELF, ru)
    print(String(format: "bench: %d polls, %.3f ms/poll (wall), objects=%d, cpu user=%.3fs sys=%.3fs", n, dt/Double(n), processObjects().count,
                 Double(ru.pointee.ru_utime.tv_sec)+Double(ru.pointee.ru_utime.tv_usec)/1e6, Double(ru.pointee.ru_stime.tv_sec)+Double(ru.pointee.ru_stime.tv_usec)/1e6))
    exit(0)
}
if let i = args.firstIndex(of: "--listen"), i+1 < args.count, let secs = Double(args[i+1]) {
    // Property listeners: process list changes, and IsRunningInput on each process object
    let q = DispatchQueue(label: "ca")
    var watched = Set<AudioObjectID>()
    func watch(_ o: AudioObjectID) {
        if watched.contains(o) { return }; watched.insert(o)
        let sel = ProcessInfo.processInfo.environment["F07_WILDCARD"] != nil ? kAudioObjectPropertySelectorWildcard : kAudioProcessPropertyIsRunningInput
        var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeWildcard, mElement: kAudioObjectPropertyElementWildcard)
        let st = AudioObjectAddPropertyListenerBlock(o, &a, q) { n, addrs in
            for k in 0..<Int(n) { let s = addrs[k].mSelector; print("  [obj \(o)] changed selector=\(String(format: "%c%c%c%c", (s>>24)&255, (s>>16)&255, (s>>8)&255, s&255))") }
            let pid = getProp(o, kAudioProcessPropertyPID, pid_t(-1)).1
            let v = getProp(o, kAudioProcessPropertyIsRunningInput, UInt32(0)).1
            print("[listener \(String(format: "%.3f", Date().timeIntervalSince1970))] IsRunningInput changed pid=\(pid) name=\(procName(pid)) -> \(v)"); fflush(stdout)
        }
        if st != noErr { print("listener add failed obj=\(o) st=\(st)") }
    }
    var la = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &la, q) { _, _ in
        processObjects().forEach(watch)
        let cap = snapshot(details: false).filter { $0.inRun }.map { "\(procName($0.pid))(\($0.pid))" }.sorted()
        print("[listener \(String(format: "%.3f", Date().timeIntervalSince1970))] process object list changed; capturing now: \(cap)"); fflush(stdout)
    }
    q.sync { processObjects().forEach(watch) }
    print("listening for \(secs)s on \(watched.count) process objects"); fflush(stdout)
    RunLoop.main.run(until: Date().addingTimeInterval(secs))
    exit(0)
}
if args.contains("--all") {
    for r in snapshot() { print("obj=\(r.obj) pid=\(r.pid) name=\(procName(r.pid)) bundle=\(r.bundle.isEmpty ? "-" : r.bundle) running=\(r.running) in=\(r.inRun) out=\(r.outRun)") }
    exit(0)
}
var loops = 1
if let i = args.firstIndex(of: "--loop"), i+1 < args.count, let n = Int(args[i+1]) { loops = n }
for k in 0..<loops { report(); fflush(stdout); if k < loops-1 { Thread.sleep(forTimeInterval: 1) } }
