// F07 helper: capture the mic with an AVAudioEngine input tap for N seconds, reporting buffer count.
import AVFoundation
let secs = Double(CommandLine.arguments.dropFirst().first ?? "10") ?? 10
print("micgrab pid=\(getpid()) auth=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)"); fflush(stdout)
let engine = AVAudioEngine()
let input = engine.inputNode
let fmt = input.outputFormat(forBus: 0)
var buffers = 0; var peak: Float = 0
input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { b, _ in
    buffers += 1
    if let d = b.floatChannelData?[0] { for i in 0..<Int(b.frameLength) { peak = max(peak, abs(d[i])) } }
}
let delay = Double(CommandLine.arguments.dropFirst(2).first ?? "0") ?? 0
if delay > 0 { print("micgrab connected to HAL, waiting \(delay)s before start"); fflush(stdout); Thread.sleep(forTimeInterval: delay) }
print(String(format: "micgrab engine.start at %.3f", Date().timeIntervalSince1970)); fflush(stdout)
do { try engine.start() } catch { print("engine start failed: \(error)"); exit(1) }
print("micgrab started format=\(fmt)"); fflush(stdout)
RunLoop.main.run(until: Date().addingTimeInterval(secs))
print("micgrab done buffers=\(buffers) peak=\(peak) (peak 0 => silence, likely TCC-denied)"); fflush(stdout)
print(String(format: "micgrab engine.stop at %.3f", Date().timeIntervalSince1970)); fflush(stdout)
engine.stop()
Thread.sleep(forTimeInterval: 3)
print(String(format: "micgrab exit at %.3f", Date().timeIntervalSince1970))
