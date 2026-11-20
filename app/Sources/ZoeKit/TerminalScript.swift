import Foundation

/// Opens a command in Terminal.app for me to run myself (#19, #20): a password prompt, an interactive login,
/// `claude /mcp`, or `claude --resume <id>`. A temporary `.command` file is opened with Terminal, which runs
/// it in a new window. No Automation (AppleScript) permission is needed.
public enum TerminalScript {
    /// Single-quotes a string for zsh.
    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The script: go to `cwd` (if it exists), show the command, run it, then leave a shell open there.
    /// The command is written as-is: it is exactly what the card showed.
    public static func script(command: String, cwd: String) -> String {
        let dir = cwd.isEmpty ? "$HOME" : quote(cwd)
        return """
        #!/bin/zsh -l
        # Opened by Zoe. The command below is exactly what Zoe's card showed.
        cd \(dir) 2>/dev/null || cd "$HOME"
        print -P "%F{cyan}[Zoe]%f in $(pwd)"
        print -r -- \(quote("$ " + command))
        \(command)
        print -P "\\n%F{cyan}[Zoe]%f Done. This window stays open as a normal shell."
        exec zsh -l

        """
    }

    /// Writes the script to a private temporary file (0700 folder, 0700 file) and returns its URL.
    public static func write(command: String, cwd: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zoe-terminal", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent("zoe-\(UUID().uuidString.prefix(8)).command")
        try script(command: command, cwd: cwd).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
