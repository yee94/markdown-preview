//
//  SidebarViewController.swift
//  md-preview
//

import Cocoa

final class SidebarViewController: NSViewController {

    enum Mode: Int {
        case outline = 0
        case files = 1
    }

    var onSelectHeading: ((Int) -> Void)?
    var onSelectFile: ((URL, String) -> Void)?
    var onModeChanged: ((Mode) -> Void)?

    private var contentContainer: NSView!
    private var scrollView: NSScrollView!
    private var outlineView: NSOutlineView!
    private var projectNavigator: ProjectNavigatorView!
    private var roots: [TOCNode] = []
    private var titleItem: TitleItem?
    private var lastRenderedMarkdown: String?
    private var lastRenderedFileName: String?
    private var loadedFolderURL: URL?
    private var pendingFolderURL: URL?
    private var pendingFileURL: URL?

    private static let modeDefaultsKey = "Sidebar.Mode"

    private(set) var currentMode: Mode = {
        Mode(rawValue: UserDefaults.standard.integer(forKey: SidebarViewController.modeDefaultsKey)) ?? .outline
    }()

    private var titleOffset: Int { titleItem == nil ? 0 : 1 }

    override func loadView() {
        let container = NSView()

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentContainer)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        contentContainer.addSubview(scrollView)

        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        // Don't grab keyboard focus — leave first responder on the document so
        // arrow / Page keys scroll the preview instead of moving the sidebar
        // selection. Click selects rows via target/action, not via focus.
        outlineView.refusesFirstResponder = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView

        projectNavigator = ProjectNavigatorView()
        projectNavigator.translatesAutoresizingMaskIntoConstraints = false
        projectNavigator.onSelectFile = { [weak self] url, source in
            self?.onSelectFile?(url, source)
        }
        contentContainer.addSubview(projectNavigator)

        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: container.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            projectNavigator.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            projectNavigator.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            projectNavigator.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            projectNavigator.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        view = container
        applyMode()
    }

    func setMode(_ newMode: Mode) {
        guard newMode != currentMode else { return }
        currentMode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeDefaultsKey)
        if isViewLoaded {
            applyMode()
            if newMode == .files {
                refreshNavigatorIfNeeded()
            }
        }
        onModeChanged?(newMode)
    }

    private func refreshNavigatorIfNeeded() {
        if pendingFolderURL != loadedFolderURL {
            loadedFolderURL = pendingFolderURL
            projectNavigator.setRoot(pendingFolderURL)
        }
        projectNavigator.setCurrentFile(pendingFileURL)
    }

    private func applyMode() {
        switch currentMode {
        case .outline:
            scrollView.isHidden = false
            projectNavigator.isHidden = true
        case .files:
            scrollView.isHidden = true
            projectNavigator.isHidden = false
        }
    }

    func display(markdown: String, fileName: String, fileURL: URL?) {
        loadViewIfNeeded()
        setOpenFileURL(fileURL)

        guard markdown != lastRenderedMarkdown || fileName != lastRenderedFileName else { return }
        lastRenderedMarkdown = markdown
        lastRenderedFileName = fileName
        titleItem = fileName.isEmpty ? nil : TitleItem(title: fileName)
        roots = MarkdownTOC.parse(markdown).map(TOCNode.init)
        outlineView.reloadData()
        for root in roots {
            outlineView.expandItem(root, expandChildren: true)
        }
        outlineView.deselectAll(nil)
    }

    /// Update the tracked file URL after a rename — keeps the navigator
    /// selection on the open file without rebuilding the TOC.
    func openFileURLDidChange(_ newURL: URL) {
        loadViewIfNeeded()
        setOpenFileURL(newURL)
    }

    /// Mounts an explicitly chosen folder as the Project Navigator root.
    /// If the current document is inside that folder, keep it selected.
    func openFolder(_ folderURL: URL, selectedFileURL: URL?) {
        loadViewIfNeeded()
        let root = folderURL.standardizedFileURL
        pendingFolderURL = root
        if let selectedFileURL, selectedFileURL.isDescendantOrSame(of: root) {
            pendingFileURL = selectedFileURL.standardizedFileURL
        } else {
            pendingFileURL = nil
        }
        if currentMode == .files {
            refreshNavigatorIfNeeded()
        }
    }

    func refreshProjectNavigator() {
        loadViewIfNeeded()
        projectNavigator.refresh()
    }

    /// Defers folder enumeration until the user is actually in the
    /// navigator (saves disk walks on every TOC-mode open). Keeps the
    /// existing root if the new file is a descendant; otherwise resets
    /// so an unrelated File → Open updates the tree.
    private func setOpenFileURL(_ fileURL: URL?) {
        let parent = fileURL?.deletingLastPathComponent().standardizedFileURL
        if let parent, let current = loadedFolderURL, parent.isDescendantOrSame(of: current) {
            pendingFolderURL = current
        } else {
            pendingFolderURL = parent
        }
        pendingFileURL = fileURL?.standardizedFileURL
        if currentMode == .files {
            refreshNavigatorIfNeeded()
        }
    }

    /// Highlights the matching TOC row. Selecting via the API doesn't
    /// dispatch the outline's action, so this won't loop back into
    /// `onSelectHeading`. We don't `scrollRowToVisible` — yanking the
    /// sidebar while the user scrolls the doc feels jumpy.
    func setActiveHeading(_ headingID: Int?) {
        loadViewIfNeeded()
        guard let headingID,
              let node = findNode(withID: headingID, in: roots) else {
            outlineView.deselectAll(nil)
            return
        }
        for ancestor in ancestors(of: node, in: roots) {
            outlineView.expandItem(ancestor)
        }
        let row = outlineView.row(forItem: node)
        guard row >= 0, outlineView.selectedRow != row else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row),
                                     byExtendingSelection: false)
    }

    private func findNode(withID id: Int, in nodes: [TOCNode]) -> TOCNode? {
        for node in nodes {
            if node.headingID == id { return node }
            if let hit = findNode(withID: id, in: node.children) { return hit }
        }
        return nil
    }

    private func ancestors(of target: TOCNode, in nodes: [TOCNode]) -> [TOCNode] {
        var path: [TOCNode] = []
        func walk(_ node: TOCNode) -> Bool {
            if node === target { return true }
            for child in node.children {
                path.append(node)
                if walk(child) { return true }
                path.removeLast()
            }
            return false
        }
        for root in nodes {
            path = []
            if walk(root) { return path }
        }
        return []
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TOCNode else { return }
        onSelectHeading?(node.headingID)
    }
}

private final class TitleItem {
    let title: String
    init(title: String) { self.title = title }
}

final class TOCNode {
    let headingID: Int
    let level: Int
    let title: String
    let children: [TOCNode]

    init(_ item: TOCItem) {
        self.headingID = item.id
        self.level = item.level
        self.title = item.title
        self.children = item.children.map(TOCNode.init)
    }
}

extension SidebarViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? TOCNode { return node.children.count }
        return roots.count + titleOffset
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? TOCNode { return node.children[index] }
        if let titleItem, index == 0 { return titleItem }
        return roots[index - titleOffset]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? TOCNode else { return false }
        return !node.children.isEmpty
    }
}

extension SidebarViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        if let titleItem = item as? TitleItem {
            return titleCell(for: titleItem, in: outlineView)
        }
        guard let node = item as? TOCNode else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("TOCCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.usesSingleLineMode = true
            textField.cell?.truncatesLastVisibleLine = true
            textField.maximumNumberOfLines = 1
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = node.title
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return item is TOCNode
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 30
    }

    private func titleCell(for titleItem: TitleItem, in outlineView: NSOutlineView) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("TitleCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            textField.textColor = .secondaryLabelColor
            textField.lineBreakMode = .byTruncatingMiddle
            textField.cell?.usesSingleLineMode = true
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 8),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)
            ])
        }
        cell.textField?.stringValue = titleItem.title
        return cell
    }
}

// MARK: - Project Navigator

private final class FileNode {
    nonisolated static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mdwn"]

    let url: URL
    let isDirectory: Bool
    let isPlaceholder: Bool
    private var loadedChildren: [FileNode]?
    private var loadingChildren = false
    /// Snapshot taken at invalidateCache(); used as a fallback when
    /// the next disk read returns empty (iCloud .revoke remount blip).
    private var previousChildren: [FileNode]?

    init(url: URL, isDirectory: Bool, isPlaceholder: Bool = false) {
        self.url = url
        self.isDirectory = isDirectory
        self.isPlaceholder = isPlaceholder
    }

    var displayName: String { isPlaceholder ? "Loading..." : url.lastPathComponent }

    /// Children if `children()` has populated the cache; nil otherwise.
    var cachedChildren: [FileNode]? { loadedChildren }
    var isLoadingChildren: Bool { loadingChildren }
    var cachedOrPreviousChildren: [FileNode]? {
        if let loadedChildren, !loadedChildren.isEmpty { return loadedChildren }
        if let previousChildren, !previousChildren.isEmpty { return previousChildren }
        return nil
    }

    /// Returns true if this directory previously had children but now
    /// reports empty after a cache invalidation (stale after iCloud blip).
    var hasStaleEmptyChildren: Bool {
        guard isDirectory else { return false }
        if let prev = previousChildren, !prev.isEmpty { return true }
        return false
    }

    func invalidateCache() {
        if let old = loadedChildren, !old.isEmpty {
            previousChildren = old
        }
        loadedChildren = nil
    }

    func children() -> [FileNode] {
        if let cached = loadedChildren { return cached }
        guard isDirectory else {
            loadedChildren = []
            return []
        }
        // Never hit the file system from NSOutlineView dataSource callbacks.
        // On network/FUSE volumes, synchronous directory reads here block the
        // main thread during layout and make the whole app feel frozen.
        if let previousChildren, !previousChildren.isEmpty {
            return previousChildren
        }
        return []
    }

    func replaceChildren(_ children: [FileNode]) {
        previousChildren = nil
        loadedChildren = children
        loadingChildren = false
    }

    func children(from entries: [FileEntry]) -> [FileNode] {
        let existingChildren = cachedOrPreviousChildren ?? []
        var existingByURL: [URL: FileNode] = [:]
        for child in existingChildren {
            existingByURL[child.url.standardizedFileURL] = child
        }
        return entries.map { entry in
            let key = entry.url.standardizedFileURL
            if let existing = existingByURL[key], existing.isDirectory == entry.isDirectory {
                return existing
            }
            return FileNode(url: entry.url, isDirectory: entry.isDirectory)
        }
    }

    func beginLoadingChildren() {
        loadingChildren = true
    }

    func endLoadingChildren() {
        loadingChildren = false
    }

    nonisolated static func loadEntries(at url: URL) -> [FileEntry] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        let nodes: [FileEntry] = entries.compactMap { entry in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { return FileEntry(url: entry, isDirectory: true) }
            guard markdownExtensions.contains(entry.pathExtension.lowercased()) else { return nil }
            return FileEntry(url: entry, isDirectory: false)
        }
        let sorted = nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        return sorted
    }
}

private struct FileEntry: Sendable {
    let url: URL
    let isDirectory: Bool

    nonisolated var displayName: String { url.lastPathComponent }
}

private final class ProjectNavigatorOutlineView: NSOutlineView {

    weak var navigator: ProjectNavigatorView?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            navigator?.selectSiblingFile(forward: false)
            return
        case 125:
            navigator?.selectSiblingFile(forward: true)
            return
        default:
            break
        }
        super.keyDown(with: event)
    }
}

final class ProjectNavigatorView: NSView {

    var onSelectFile: ((URL, String) -> Void)?

    private let scrollView = NSScrollView()
    private let outlineView = ProjectNavigatorOutlineView()
    private var rootNode: FileNode?
    /// The file currently shown in the preview; drives sibling navigation.
    private var previewFileURL: URL?
    private var folderChangeWork: DispatchWorkItem?
    private let directoryLoadQueue = DispatchQueue(label: "doc.md-preview.project-navigator.load",
                                                   qos: .utility)
    private var loadingDirectories: Set<URL> = []
    private var navigatorLoadGeneration = 0
    private var emptyDirectoryRetryCounts: [URL: Int] = [:]
    // One watcher per loaded directory; kept in sync with which FileNodes
    // currently have a populated children cache.
    private var watchers: [URL: DirectoryWatcher] = [:]
    private static let folderIcon = makeTemplateIcon("folder")
    private static let documentIcon = makeTemplateIcon("doc.text")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        addSubview(scrollView)

        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.doubleAction = #selector(rowDoubleClicked)
        outlineView.indentationPerLevel = 14
        outlineView.navigator = self

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func refresh() {
        refreshTree()
    }

    func setRoot(_ url: URL?) {
        cancelAllWatchers()
        loadingDirectories.removeAll()
        emptyDirectoryRetryCounts.removeAll()
        navigatorLoadGeneration += 1
        rootNode = url.map { FileNode(url: $0.standardizedFileURL, isDirectory: true) }
        outlineView.reloadData()
        if let rootNode {
            outlineView.expandItem(rootNode)
            requestChildrenLoad(for: rootNode, reloadParent: nil)
        }
    }

    // MARK: - Folder watching

    private func syncWatchers() {
        // Project Navigator is intentionally snapshot-based for network/FUSE
        // volumes. Automatic file-system reloads can invalidate the visible
        // tree while the volume is remounting; users refresh explicitly.
    }

    private func collectLoadedDirectories(_ node: FileNode, into set: inout Set<URL>) {
        guard node.isDirectory else { return }
        set.insert(node.url.standardizedFileURL)
        guard let kids = node.cachedChildren else { return }
        for child in kids where child.isDirectory {
            collectLoadedDirectories(child, into: &set)
        }
    }

    private func cancelAllWatchers() {
        folderChangeWork?.cancel()
        folderChangeWork = nil
        staleCheckWork?.cancel()
        staleCheckWork = nil
        for watcher in watchers.values { watcher.cancel() }
        watchers.removeAll()
    }

    private func requestChildrenLoad(for node: FileNode, reloadParent parent: FileNode?) {
        guard node.isDirectory else { return }
        let url = node.url.standardizedFileURL
        guard !loadingDirectories.contains(url) else { return }
        loadingDirectories.insert(url)
        node.beginLoadingChildren()
        let generation = navigatorLoadGeneration
        PreviewDebugLog.event("navigator.load.request", [
            "generation": generation,
            "url": url.path,
            "hasSnapshot": node.cachedOrPreviousChildren != nil
        ])
        directoryLoadQueue.async { [weak self, weak node, weak parent] in
            PreviewDebugLog.event("navigator.load.start", [
                "generation": generation,
                "url": url.path
            ])
            let entries = FileNode.loadEntries(at: url)
            PreviewDebugLog.event("navigator.load.finish", [
                "generation": generation,
                "url": url.path,
                "entries": entries.count,
                "directories": entries.filter(\.isDirectory).count,
                "files": entries.filter { !$0.isDirectory }.count
            ])
            DispatchQueue.main.async {
                guard let self, let node else { return }
                guard self.navigatorLoadGeneration == generation else {
                    PreviewDebugLog.event("navigator.load.drop", [
                        "reason": "stale_generation",
                        "generation": generation,
                        "currentGeneration": self.navigatorLoadGeneration,
                        "url": url.path
                    ])
                    return
                }
                self.loadingDirectories.remove(url)
                let children = node.children(from: entries)
                let reusedChildren = children.filter { child in
                    node.cachedOrPreviousChildren?.contains { $0 === child } == true
                }.count
                // Network volumes can transiently report empty while the old
                // snapshot is still the better UX. Keep the old cache in that
                // case; the refresh button gives users an explicit retry.
                if children.isEmpty,
                   let snapshot = node.cachedOrPreviousChildren,
                   !snapshot.isEmpty {
                    node.endLoadingChildren()
                    PreviewDebugLog.event("navigator.load.keep_snapshot", [
                        "generation": generation,
                        "url": url.path,
                        "snapshotChildren": snapshot.count
                    ])
                    return
                }
                if !children.isEmpty {
                    self.emptyDirectoryRetryCounts[url] = nil
                }
                let wasExpanded = self.outlineView.isItemExpanded(node)
                node.replaceChildren(children)
                PreviewDebugLog.event("navigator.load.apply", [
                    "generation": generation,
                    "url": url.path,
                    "children": children.count,
                    "reusedChildren": reusedChildren,
                    "wasExpanded": wasExpanded
                ])
                if let parent {
                    self.outlineView.reloadItem(parent, reloadChildren: true)
                } else {
                    self.outlineView.reloadItem(node, reloadChildren: true)
                    if node === self.rootNode || wasExpanded {
                        self.outlineView.expandItem(node)
                    }
                }
                self.syncWatchers()
                if let previewFileURL = self.previewFileURL {
                    self.setCurrentFile(previewFileURL)
                }
            }
        }
    }

    @discardableResult
    private func scheduleEmptyDirectoryRetry(for node: FileNode) -> Bool {
        let url = node.url.standardizedFileURL
        let attempts = emptyDirectoryRetryCounts[url, default: 0]
        guard attempts < 4 else { return false }
        emptyDirectoryRetryCounts[url] = attempts + 1
        let delay = min(8.0, pow(2.0, Double(attempts)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak node] in
            guard let self, let node else { return }
            self.requestChildrenLoad(for: node, reloadParent: nil)
        }
        return true
    }

    private func handleFolderChange() {
        folderChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let selectedURL = self.currentlySelectedURL()
            self.refreshTree()
            if let selectedURL { self.setCurrentFile(selectedURL) }
        }
        folderChangeWork = work
        // Directory watchers can fire once per expanded folder on network /
        // FUSE volumes. Coalesce them into one outline reload so AppKit does
        // not spend seconds rebuilding row views on the main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Reloads the outline from disk while preserving expansion state.
    /// Selection is left to the caller.
    private func refreshTree() {
        let expandedURLs = collectExpandedURLs()
        navigatorLoadGeneration += 1
        loadingDirectories.removeAll()
        emptyDirectoryRetryCounts.removeAll()
        PreviewDebugLog.event("navigator.refresh", [
            "generation": navigatorLoadGeneration,
            "expanded": expandedURLs.count,
            "root": rootNode?.url.path ?? "nil"
        ])
        if let rootNode { invalidateCaches(rootNode) }
        outlineView.reloadData()
        if let rootNode {
            outlineView.expandItem(rootNode)
            reExpand(rootNode, expanded: expandedURLs)
            requestChildrenLoad(for: rootNode, reloadParent: nil)
            requestLoads(for: rootNode, expanded: expandedURLs)
        }
        syncWatchers()
    }

    // MARK: - Stale cache recovery

    private var staleCheckWork: DispatchWorkItem?

    private func scheduleStaleCheck() {
        staleCheckWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let rootNode = self.rootNode else { return }
            if self.hasStaleEmptyDirectory(rootNode) {
                self.refreshTree()
            }
        }
        staleCheckWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// Returns true if any directory node has a pre-invalidate snapshot
    /// but the current disk read returned empty (iCloud remount blip).
    private func hasStaleEmptyDirectory(_ node: FileNode) -> Bool {
        guard node.isDirectory else { return false }
        if node.hasStaleEmptyChildren { return true }
        return node.cachedChildren?.contains(where: hasStaleEmptyDirectory) ?? false
    }

    private func invalidateCaches(_ node: FileNode) {
        guard node.isDirectory, let kids = node.cachedChildren else { return }
        for child in kids where child.isDirectory {
            invalidateCaches(child)
        }
        node.invalidateCache()
    }

    private func requestLoads(for node: FileNode, expanded: Set<URL>) {
        guard node.isDirectory else { return }
        if expanded.contains(node.url.standardizedFileURL) {
            requestChildrenLoad(for: node, reloadParent: nil)
        }
        for child in node.children() where child.isDirectory {
            requestLoads(for: child, expanded: expanded)
        }
    }

    private static func makeTemplateIcon(_ systemName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    private func collectExpandedURLs() -> Set<URL> {
        var result: Set<URL> = []
        func walk(_ item: Any?) {
            let count = outlineView.numberOfChildren(ofItem: item)
            for i in 0..<count {
                let child = outlineView.child(i, ofItem: item)
                if let node = child as? FileNode, outlineView.isItemExpanded(node) {
                    result.insert(node.url.standardizedFileURL)
                    walk(child)
                }
            }
        }
        walk(nil)
        return result
    }

    private func currentlySelectedURL() -> URL? {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode,
              !node.isPlaceholder else { return nil }
        return node.url.standardizedFileURL
    }

    private func reExpand(_ node: FileNode, expanded: Set<URL>) {
        guard node.isDirectory else { return }
        for child in node.children() where child.isDirectory {
            if expanded.contains(child.url.standardizedFileURL) {
                outlineView.expandItem(child)
                reExpand(child, expanded: expanded)
            }
        }
    }

    func setCurrentFile(_ url: URL?) {
        previewFileURL = url?.standardizedFileURL
        guard let url, let rootNode else {
            outlineView.deselectAll(nil)
            return
        }
        let target = url.standardizedFileURL
        var path: [FileNode] = []
        if !collectPath(to: target, from: rootNode, into: &path) {
            requestChildrenLoad(for: rootNode, reloadParent: nil)
            outlineView.deselectAll(nil)
            return
        }
        for ancestor in path.dropLast() {
            outlineView.expandItem(ancestor)
        }
        if let leaf = path.last {
            let row = outlineView.row(forItem: leaf)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        }
    }

    private func collectPath(to targetURL: URL,
                             from root: FileNode,
                             into path: inout [FileNode]) -> Bool {
        // Skip subtrees that can't contain the target.
        guard targetURL.isDescendantOrSame(of: root.url) else { return false }

        for child in root.children() {
            if child.url.standardizedFileURL == targetURL {
                path.append(child)
                return true
            }
            if child.isDirectory {
                path.append(child)
                if collectPath(to: targetURL, from: child, into: &path) { return true }
                path.removeLast()
            }
        }
        return false
    }

    /// Moves the preview to the previous or next markdown file in the
    /// same directory. No-op when already at the boundary.
    fileprivate func selectSiblingFile(forward: Bool) {
        guard let rootNode,
              let currentURL = previewFileURL ?? currentlySelectedFileURL() else { return }
        guard let siblings = siblingMarkdownFiles(for: currentURL, from: rootNode),
              let index = siblings.firstIndex(where: { $0.url.standardizedFileURL == currentURL }) else { return }
        let nextIndex = forward ? index + 1 : index - 1
        guard siblings.indices.contains(nextIndex) else { return }
        let nextURL = siblings[nextIndex].url
        previewFileURL = nextURL.standardizedFileURL
        setCurrentFile(nextURL)
        onSelectFile?(nextURL, "sidebar.keyboard")
    }

    private func currentlySelectedFileURL() -> URL? {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode,
              !node.isDirectory,
              !node.isPlaceholder else { return nil }
        return node.url.standardizedFileURL
    }

    private func siblingMarkdownFiles(for fileURL: URL, from root: FileNode) -> [FileNode]? {
        let parentURL = fileURL.deletingLastPathComponent().standardizedFileURL
        guard let parent = findDirectoryNode(for: parentURL, from: root) else { return nil }
        let files = parent.children().filter { !$0.isDirectory && !$0.isPlaceholder }
        return files.isEmpty ? nil : files
    }

    private func findDirectoryNode(for directoryURL: URL, from root: FileNode) -> FileNode? {
        let target = directoryURL.standardizedFileURL
        if root.url.standardizedFileURL == target { return root }
        return findDirectoryNode(for: target, under: root)
    }

    private func findDirectoryNode(for target: URL, under node: FileNode) -> FileNode? {
        for child in node.children() where child.isDirectory {
            if child.url.standardizedFileURL == target { return child }
            if target.isDescendantOrSame(of: child.url),
               let found = findDirectoryNode(for: target, under: child) {
                return found
            }
        }
        return nil
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        guard !node.isPlaceholder else { return }
        if !node.isDirectory {
            previewFileURL = node.url.standardizedFileURL
            onSelectFile?(node.url, "sidebar.click")
        }
    }

    @objc private func rowDoubleClicked() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        guard !node.isPlaceholder else { return }
        guard node.isDirectory else { return }
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            outlineView.expandItem(node)
        }
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openInNewWindow(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let controller = documentWindowController else { return }
        controller.openInNewWindow(url)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc private func copyContents(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task { @concurrent in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }
}

extension ProjectNavigatorView: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        guard !node.isPlaceholder else { return }
        let url = node.url

        menu.addItem(makeMenuItem(title: "Show in Finder",
                                  symbol: "folder",
                                  action: #selector(showInFinder(_:)),
                                  url: url))

        if !node.isDirectory {
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: "Open in New Window",
                                      symbol: "macwindow.badge.plus",
                                      action: #selector(openInNewWindow(_:)),
                                      url: url))
            if let controller = documentWindowController {
                for item in controller.contextMenuEditorItems(for: url) {
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: "Copy",
                                      symbol: "document.on.clipboard",
                                      action: #selector(copyContents(_:)),
                                      url: url))
        } else {
            menu.addItem(.separator())
        }

        menu.addItem(makeMenuItem(title: "Copy Path",
                                  symbol: "document.on.document",
                                  action: #selector(copyPath(_:)),
                                  url: url))
    }

    private func makeMenuItem(title: String,
                              symbol: String,
                              action: Selector,
                              url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private var documentWindowController: DocumentWindowController? {
        outlineView.window?.windowController as? DocumentWindowController
    }
}

extension ProjectNavigatorView: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? FileNode {
            if node.isDirectory, node.cachedChildren == nil {
                requestChildrenLoad(for: node, reloadParent: nil)
            }
            return node.children().count
        }
        return rootNode == nil ? 0 : 1
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FileNode { return node.children()[index] }
        return rootNode!
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        if node.isDirectory, node.cachedChildren == nil {
            requestChildrenLoad(for: node, reloadParent: nil)
            return true
        }
        return node.isDirectory && !node.children().isEmpty
    }
}

extension ProjectNavigatorView: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.usesSingleLineMode = true
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = node.displayName
        // Avoid NSWorkspace.icon(forFile:) here. On itfs/FUSE paths that call
        // enters IconServices for every visible row during outline reloads and
        // can stall the main thread. Generic template icons keep row creation
        // deterministic and cheap.
        cell.imageView?.image = node.isDirectory ? Self.folderIcon : Self.documentIcon
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 24
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        // Newly-loaded subtree needs its own watcher.
        if let node = notification.userInfo?["NSObject"] as? FileNode,
           node.cachedChildren == nil {
            requestChildrenLoad(for: node, reloadParent: nil)
        }
        syncWatchers()
    }
}

private final class DirectoryWatcher {
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                Darwin.close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    /// FS events arrive in bursts (Finder rewrites + xattr updates). Coalesce.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func cancel() {
        debounce?.cancel()
        source?.cancel()
        source = nil
    }
}
