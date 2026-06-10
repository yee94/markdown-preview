//
//  PreviewDebugLog.swift
//  md-preview
//

import Foundation

/// Append-only preview pipeline trace. Disabled by default; enable with
/// `MD_PREVIEW_TRACE=1` or `defaults write doc.md-preview PreviewTraceEnabled -bool YES`,
/// then run `./scripts/show-preview-debug-log.sh`.
enum PreviewDebugLog {
    nonisolated(unsafe) static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["MD_PREVIEW_TRACE"] == "1"
            || UserDefaults.standard.bool(forKey: "PreviewTraceEnabled")
    }()

    private nonisolated(unsafe) static var origin = DispatchTime.now()
    private nonisolated(unsafe) static var sequence: UInt64 = 0

    private nonisolated(unsafe) static let queue = DispatchQueue(label: "doc.md-preview.debuglog")

    nonisolated static var fileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("preview-trace.jsonl", isDirectory: false)
    }

    nonisolated static func resetSession() {
        guard isEnabled else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let header = makeLine(event: "session.start", fields: [
            "time": ISO8601DateFormatter().string(from: Date()),
            "pid": ProcessInfo.processInfo.processIdentifier,
            "version": version,
            "build": build,
            "app": Bundle.main.bundlePath,
            "log": fileURL.path
        ])
        queue.sync {
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        origin = DispatchTime.now()
        sequence = 0
    }

    nonisolated static func write(_ message: String) {
        event("message", ["text": message])
    }

    nonisolated static func event(_ name: String, _ fields: [String: Any] = [:]) {
        guard isEnabled else { return }
        let line = makeLine(event: name, fields: fields)
        let url = fileURL
        queue.async {
            append(line, to: url)
        }
    }

    nonisolated static func hash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private nonisolated static func makeLine(event: String, fields: [String: Any]) -> String {
        let now = DispatchTime.now().uptimeNanoseconds
        let start = origin.uptimeNanoseconds
        let elapsedNanoseconds = now >= start ? now - start : 0
        let elapsedMs = Int(
            (Double(elapsedNanoseconds) / 1_000_000).rounded()
        )
        sequence &+= 1
        var payload = fields
        payload["event"] = event
        payload["elapsedMs"] = elapsedMs
        payload["seq"] = sequence
        payload["thread"] = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg")
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return "{\"event\":\"trace.encode_failed\"}\n"
        }
        return line + "\n"
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
