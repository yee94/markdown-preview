//
//  PreviewDebugLog.swift
//  md-preview
//

import Foundation

/// Append-only preview pipeline log. Disabled by default; flip `isEnabled` to
/// `true` when diagnosing itfs / WebView issues, then run
/// `./scripts/show-preview-debug-log.sh`.
enum PreviewDebugLog {
    nonisolated(unsafe) static var isEnabled = false

    private nonisolated(unsafe) static var origin = DispatchTime.now()

    private nonisolated(unsafe) static let queue = DispatchQueue(label: "doc.md-preview.debuglog")

    nonisolated static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("preview-debug.log", isDirectory: false)
    }

    nonisolated static func resetSession() {
        guard isEnabled else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let header = """
        === Markdown Preview debug session ===
        time=\(ISO8601DateFormatter().string(from: Date()))
        pid=\(ProcessInfo.processInfo.processIdentifier)
        version=\(version) (\(build))
        app=\(Bundle.main.bundlePath)
        log=\(fileURL.path)
        ======================================

        """
        queue.sync {
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        origin = DispatchTime.now()
    }

    nonisolated static func write(_ message: String) {
        guard isEnabled else { return }
        let elapsedMs = Int(
            (Double(DispatchTime.now().uptimeNanoseconds - origin.uptimeNanoseconds)
             / 1_000_000).rounded()
        )
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg")
        let line = "[t+\(elapsedMs)ms][\(thread)] \(message)\n"
        let url = fileURL
        queue.async {
            append(line, to: url)
        }
    }

    private static func append(_ line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
