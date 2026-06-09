//
//  WelcomeWindowController.swift
//  md-preview
//

import Cocoa

/// Standalone startup window — keeps the document window for browsing only.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    var onChooseFolder: ((URL) -> Void)?

    private let welcomeViewController = WelcomeViewController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown Preview"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        setUpWelcomeViewController()
        window.contentViewController = welcomeViewController
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isOnScreen: Bool {
        guard let window, window.isVisible else { return false }
        guard let screen = window.screen ?? NSScreen.main else { return true }
        return screen.visibleFrame.intersects(window.frame)
    }

    func present() {
        welcomeViewController.reloadRecentFolders()
        showWindow(nil)
        placeWindowOnScreen()
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeWindowOnScreen() {
        guard let window else { return }
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        guard let screen = window.screen ?? NSScreen.main else { return }
        var frame = window.frame
        if !screen.visibleFrame.intersects(frame) {
            let visible = screen.visibleFrame
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2
            window.setFrame(frame, display: true)
        }
    }

    private func setUpWelcomeViewController() {
        welcomeViewController.onOpenFolder = { [weak self] in
            self?.promptForFolder()
        }
        welcomeViewController.onCreateFolder = { [weak self] in
            self?.promptForNewFolder()
        }
        welcomeViewController.onCloneRepository = { [weak self] in
            self?.promptForGitClone()
        }
        welcomeViewController.onSelectRecentFolder = { [weak self] url in
            self?.chooseFolder(url)
        }
    }

    private func chooseFolder(_ url: URL) {
        onChooseFolder?(url.standardizedFileURL)
    }

    private var hostWindow: NSWindow {
        guard let window else {
            fatalError("WelcomeWindowController accessed before its window was loaded")
        }
        return window
    }

    private func promptForFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder to browse"
        panel.beginSheetModal(for: hostWindow) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.chooseFolder(url)
        }
    }

    private func promptForNewFolder() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Create"
        panel.message = "Choose where to create the new folder"
        panel.nameFieldStringValue = "Untitled Folder"
        panel.beginSheetModal(for: hostWindow) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try FileManager.default.createDirectory(at: url,
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
                self.chooseFolder(url)
            } catch {
                NSAlert(error: error).beginSheetModal(for: self.hostWindow)
            }
        }
    }

    private func promptForGitClone() {
        let alert = NSAlert()
        alert.messageText = "Clone Git Repository"
        alert.informativeText = "Enter a repository URL and choose a parent folder."
        alert.addButton(withTitle: "Clone")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://github.com/user/repo.git"
        alert.accessoryView = field

        alert.beginSheetModal(for: hostWindow) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let repoURL = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !repoURL.isEmpty else { return }

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Clone Here"
            panel.message = "Choose where to clone the repository"
            panel.beginSheetModal(for: self.hostWindow) { [weak self] panelResponse in
                guard let self, panelResponse == .OK, let parent = panel.url else { return }
                self.cloneRepository(repoURL, into: parent)
            }
        }
    }

    private func cloneRepository(_ repoURL: String, into parent: URL) {
        let rawName = repoURL.split(separator: "/").last.map(String.init) ?? "repository"
        let folderName = rawName.hasSuffix(".git") ? String(rawName.dropLast(4)) : rawName
        let destination = parent.appendingPathComponent(folderName, isDirectory: true)

        Task { @concurrent [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["clone", repoURL, destination.path]

            do {
                try process.run()
                process.waitUntilExit()
                let status = process.terminationStatus
                await MainActor.run {
                    guard let self else { return }
                    guard status == 0 else {
                        let alert = NSAlert()
                        alert.messageText = "Clone Failed"
                        alert.informativeText = "git clone exited with status \(status)."
                        alert.beginSheetModal(for: self.hostWindow)
                        return
                    }
                    self.chooseFolder(destination)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    NSAlert(error: error).beginSheetModal(for: self.hostWindow)
                }
            }
        }
    }
}
