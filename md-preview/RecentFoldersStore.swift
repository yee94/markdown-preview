//
//  RecentFoldersStore.swift
//  md-preview
//

import Foundation

/// Persists recently opened project folders for the welcome screen.
enum RecentFoldersStore {

    private static let defaultsKey = "MarkdownPreview.recentFolders"
    private static let maxEntries = 20

    struct Entry: Equatable {
        let url: URL
        let name: String
        let abbreviatedPath: String
    }

    static func record(_ folderURL: URL) {
        let url = folderURL.standardizedFileURL
        guard url.isExistingDirectory else { return }

        var paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > maxEntries {
            paths = Array(paths.prefix(maxEntries))
        }
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    static func entries(limit: Int? = nil) -> [Entry] {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let capped = limit.map { Array(paths.prefix($0)) } ?? paths
        return capped.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            return Entry(url: url,
                         name: url.lastPathComponent,
                         abbreviatedPath: abbreviatedPath(for: url))
        }
    }

    static func abbreviatedPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}
