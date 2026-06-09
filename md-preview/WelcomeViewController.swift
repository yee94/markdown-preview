//
//  WelcomeViewController.swift
//  md-preview
//

import Cocoa

/// Cold-start landing page: quick actions and recently opened folders.
final class WelcomeViewController: NSViewController {

    var onOpenFolder: (() -> Void)?
    var onCreateFolder: (() -> Void)?
    var onCloneRepository: (() -> Void)?
    var onSelectRecentFolder: ((URL) -> Void)?

    private static let collapsedRecentLimit = 5

    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private let contentStack = NSStackView()
    private let actionStack = NSStackView()
    private let recentHeaderLabel = NSTextField(labelWithString: "Recent Folders")
    private let recentSeparator = HairlineSeparator()
    private let recentRowsStack = NSStackView()
    private let moreButton = NSButton(title: "More", target: nil, action: nil)

    private var isExpanded = false

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root
        setUpHierarchy()
        reloadRecentFolders()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        centerContentIfNeeded()
    }

    func reloadRecentFolders() {
        recentRowsStack.arrangedSubviews.forEach {
            recentRowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let limit = isExpanded ? nil : Self.collapsedRecentLimit
        let entries = RecentFoldersStore.entries(limit: limit)
        for entry in entries {
            let row = makeRecentRow(for: entry)
            recentRowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: recentRowsStack.widthAnchor).isActive = true
        }

        let totalCount = RecentFoldersStore.entries().count
        moreButton.isHidden = totalCount <= Self.collapsedRecentLimit
        if !isExpanded {
            moreButton.title = "More"
        }
    }

    private func setUpHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        view.addSubview(scrollView)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 28
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 12
        actionStack.addArrangedSubview(makeActionButton(title: "New Folder",
                                                        symbol: "folder.badge.plus",
                                                        action: #selector(createFolderTapped)))
        actionStack.addArrangedSubview(makeActionButton(title: "Open Folder",
                                                        symbol: "folder",
                                                        action: #selector(openFolderTapped)))
        actionStack.addArrangedSubview(makeActionButton(title: "Clone Git Repository",
                                                        symbol: "arrow.triangle.branch",
                                                        action: #selector(cloneRepositoryTapped)))
        contentStack.addArrangedSubview(actionStack)

        recentHeaderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        recentHeaderLabel.textColor = .secondaryLabelColor
        contentStack.addArrangedSubview(recentHeaderLabel)

        recentSeparator.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(recentSeparator)
        recentSeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        recentRowsStack.orientation = .vertical
        recentRowsStack.alignment = .leading
        recentRowsStack.spacing = 0
        contentStack.addArrangedSubview(recentRowsStack)
        recentRowsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        moreButton.bezelStyle = .inline
        moreButton.isBordered = false
        moreButton.font = .systemFont(ofSize: 13)
        moreButton.contentTintColor = .secondaryLabelColor
        moreButton.target = self
        moreButton.action = #selector(moreTapped)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(moreButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 48),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 48),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -48),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -48),
            contentStack.widthAnchor.constraint(lessThanOrEqualToConstant: 720),

            contentStack.centerXAnchor.constraint(equalTo: documentView.centerXAnchor)
        ])
    }

    private func centerContentIfNeeded() {
        let contentHeight = contentStack.fittingSize.height + 96
        let visibleHeight = scrollView.contentView.bounds.height
        documentView.frame.size.height = max(contentHeight, visibleHeight)
    }

    private func makeActionButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = WelcomeActionButton(title: title, symbolName: symbol)
        button.target = self
        button.action = action
        return button
    }

    private func makeRecentRow(for entry: RecentFoldersStore.Entry) -> NSView {
        let row = RecentFolderRowView(entry: entry)
        row.onClick = { [weak self] url in
            self?.onSelectRecentFolder?(url)
        }
        return row
    }

    @objc private func openFolderTapped() {
        onOpenFolder?()
    }

    @objc private func createFolderTapped() {
        onCreateFolder?()
    }

    @objc private func cloneRepositoryTapped() {
        onCloneRepository?()
    }

    @objc private func moreTapped() {
        isExpanded.toggle()
        reloadRecentFolders()
        view.needsLayout = true
    }
}

// MARK: - Action button

private final class WelcomeActionButton: NSButton {

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .accessoryBarAction
        controlSize = .large
        font = .systemFont(ofSize: 13)
        imagePosition = .imageLeading
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(symbolConfig) {
            image.isTemplate = true
            self.image = image
        }
        contentTintColor = .labelColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        super.updateLayer()
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
    }
}

// MARK: - Recent row

private final class RecentFolderRowView: NSControl {

    var onClick: ((URL) -> Void)?

    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let entry: RecentFoldersStore.Entry
    private var isHovered = false

    init(entry: RecentFoldersStore.Entry) {
        self.entry = entry
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUp() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true

        nameLabel.stringValue = entry.name
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.stringValue = entry.abbreviatedPath
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.alignment = .right
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLabel)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: pathLabel.leadingAnchor, constant: -16),

            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])

        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil)
        addTrackingArea(tracking)
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = 6
        layer?.backgroundColor = (isHovered ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35) : .clear).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(entry.url)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}
