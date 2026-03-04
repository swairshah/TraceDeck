//
//  NotchOverlayController.swift
//  TraceDeck
//

import AppKit
import Combine
import QuartzCore

private enum NotchOverlayConstants {
    static let collapsedWidth: CGFloat = 300
    static let expandedWidth: CGFloat = 360
    static let expandedHeight: CGFloat = 120
    static let searchExpandedWidth: CGFloat = 420
    static let searchExpandedHeight: CGFloat = 340

    static let collapsedHeightWithNotch: CGFloat = 36
    static let collapsedHeightWithoutNotch: CGFloat = 25
    static let shoulderSizeWithNotch: CGFloat = 16
    static let shoulderSizeWithoutNotch: CGFloat = 12
    static let bottomRadiusWithNotch: CGFloat = 22
    static let bottomRadiusWithoutNotch: CGFloat = 10

    static let openDuration: TimeInterval = 0.5
    static let expandDuration: TimeInterval = 0.25
    static let collapseDuration: TimeInterval = 0.2

    static let hoverPadding: CGFloat = 30
    static let debounceInterval: TimeInterval = 0.02

    static let sectionRadius: CGFloat = 14
    static let chipRadius: CGFloat = 10

    static let sectionColor = NSColor(white: 0.14, alpha: 1)
    static let chipColor = NSColor(white: 0.22, alpha: 1)
    static let dimText = NSColor(white: 0.45, alpha: 1)

    static func collapsedHeight(hasNotch: Bool) -> CGFloat {
        hasNotch ? collapsedHeightWithNotch : collapsedHeightWithoutNotch
    }

    static func shoulderSize(hasNotch: Bool) -> CGFloat {
        hasNotch ? shoulderSizeWithNotch : shoulderSizeWithoutNotch
    }

    static func bottomRadiusLimit(hasNotch: Bool) -> CGFloat {
        hasNotch ? bottomRadiusWithNotch : bottomRadiusWithoutNotch
    }
}

private struct NotchOverlayInfo {
    let centerX: CGFloat
    let topY: CGFloat
    let notchWidth: CGFloat
    let hasNotch: Bool
}

private enum NotchOverlayDetector {
    static func detect() -> NotchOverlayInfo {
        guard let screen = NSScreen.main else {
            return NotchOverlayInfo(centerX: 0, topY: 0, notchWidth: NotchOverlayConstants.collapsedWidth, hasNotch: false)
        }

        let frame = screen.frame

        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           left != .zero,
           right != .zero {
            let notchWidth = right.minX - left.maxX
            let centerX = left.maxX + notchWidth / 2
            return NotchOverlayInfo(centerX: centerX, topY: frame.maxY, notchWidth: notchWidth, hasNotch: true)
        }

        return NotchOverlayInfo(centerX: frame.midX, topY: frame.maxY, notchWidth: NotchOverlayConstants.collapsedWidth, hasNotch: false)
    }
}

private final class NotchOverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar + 1
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Content View

private final class NotchOverlayContentView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Callbacks — controller wires these up
    var onToggleRecording: (() -> Void)?
    var onSessionNoteChanged: ((String) -> Void)?
    var onSearchIconClicked: (() -> Void)?
    var onSearchSubmitted: ((String) -> Void)?

    @objc dynamic var shapeMorphProgress: CGFloat {
        get { internalShapeMorphProgress }
        set {
            let clamped = min(max(newValue, 0), 1)
            guard clamped != internalShapeMorphProgress else { return }
            internalShapeMorphProgress = clamped
            needsLayout = true
        }
    }

    private let shapeMask = CAShapeLayer()
    private var internalShapeMorphProgress: CGFloat = 1

    // Top bar
    private var dotView: NSView!
    private var searchIcon: NSImageView!
    private var timerDisplay: NSTextField!
    private var timerHovered = false
    private var timerTrackingArea: NSTrackingArea?

    // Expanded recording panel
    private var gearIcon: NSImageView!
    private var expandedPanel: NSView!
    private var timerRow: NSView!
    private var durationChip: NSView!
    private var durationLabel: NSTextField!
    private var taskLabel: NSTextField!
    private var playChip: NSView!
    private var playIcon: NSImageView!
    private var stopChip: NSView!
    private var stopIcon: NSImageView!

    // Search panel (replaces expandedPanel when in search mode)
    private var searchPanel: NSView!
    private var searchRow: NSView!
    private var searchField: NSTextField!
    private var searchSpinner: NSProgressIndicator!
    private var searchResultsScroll: NSScrollView!
    private var searchResultsStack: NSStackView!
    private var searchPlaceholder: NSTextField!

    private var isRecording = false
    private var recordingStartedAt: Date?
    private var elapsedTimer: Timer?
    private var hasNotch = false
    private(set) var isSearchMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        if key == "shapeMorphProgress" { return CABasicAnimation() }
        return super.defaultAnimation(forKey: key)
    }

    deinit {
        elapsedTimer?.invalidate()
    }

    // MARK: Build UI

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        shapeMask.fillColor = NSColor.white.cgColor
        layer?.mask = shapeMask

        buildTopBar()
        buildRecordingPanel()
        buildSearchPanel()
        timerDisplay.alphaValue = 0  // hidden in collapsed state
        update(recording: AppState.shared.isRecording)
    }

    private func buildTopBar() {
        dotView = NSView()
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 5
        addSubview(dotView)

        if let image = sfImage("magnifyingglass", size: 11, weight: .medium) {
            searchIcon = NSImageView(image: image)
            searchIcon.contentTintColor = NotchOverlayConstants.dimText
        } else {
            searchIcon = NSImageView()
        }
        addSubview(searchIcon)

        timerDisplay = makeLabel("REC", size: 11, weight: .medium)
        timerDisplay.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        addSubview(timerDisplay)
    }

    private func buildRecordingPanel() {
        if let image = sfImage("gearshape", size: 14, weight: .medium) {
            gearIcon = NSImageView(image: image)
            gearIcon.contentTintColor = NotchOverlayConstants.dimText
        } else {
            gearIcon = NSImageView()
        }
        gearIcon.alphaValue = 0
        addSubview(gearIcon)

        expandedPanel = FlippedView()
        expandedPanel.wantsLayer = true
        expandedPanel.alphaValue = 0
        addSubview(expandedPanel)

        timerRow = roundedBox(NotchOverlayConstants.sectionColor, radius: NotchOverlayConstants.sectionRadius)
        expandedPanel.addSubview(timerRow)

        durationChip = roundedBox(NotchOverlayConstants.chipColor, radius: NotchOverlayConstants.chipRadius)
        durationLabel = makeLabel("Record", size: 13, weight: .semibold)
        durationChip.addSubview(durationLabel)
        timerRow.addSubview(durationChip)

        taskLabel = NSTextField()
        taskLabel.placeholderAttributedString = NSAttributedString(
            string: "Session note (optional)",
            attributes: [
                .foregroundColor: NSColor(white: 0.45, alpha: 1),
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        taskLabel.font = .systemFont(ofSize: 13)
        taskLabel.textColor = .white
        taskLabel.backgroundColor = .clear
        taskLabel.isBezeled = false
        taskLabel.focusRingType = .none
        taskLabel.isEditable = false
        taskLabel.isSelectable = false
        taskLabel.drawsBackground = false
        taskLabel.delegate = self
        taskLabel.stringValue = AppState.shared.sessionNoteDraft
        timerRow.addSubview(taskLabel)

        playChip = roundedBox(NotchOverlayConstants.chipColor, radius: NotchOverlayConstants.chipRadius)
        if let image = sfImage("record.circle.fill", size: 12, weight: .medium) {
            playIcon = NSImageView(image: image)
            playIcon.contentTintColor = .white
        } else {
            playIcon = NSImageView()
        }
        playChip.addSubview(playIcon)
        timerRow.addSubview(playChip)

        stopChip = roundedBox(NotchOverlayConstants.chipColor, radius: NotchOverlayConstants.chipRadius)
        if let image = sfImage("stop.fill", size: 12, weight: .medium) {
            stopIcon = NSImageView(image: image)
            stopIcon.contentTintColor = .white
        } else {
            stopIcon = NSImageView()
        }
        stopChip.addSubview(stopIcon)
        stopChip.isHidden = true
        timerRow.addSubview(stopChip)
    }

    private func buildSearchPanel() {
        searchPanel = FlippedView()
        searchPanel.wantsLayer = true
        searchPanel.alphaValue = 0
        searchPanel.isHidden = true
        addSubview(searchPanel)

        searchRow = roundedBox(NotchOverlayConstants.sectionColor, radius: NotchOverlayConstants.sectionRadius)
        searchPanel.addSubview(searchRow)

        searchField = NSTextField()
        searchField.placeholderAttributedString = NSAttributedString(
            string: "Search your activity…",
            attributes: [
                .foregroundColor: NSColor(white: 0.45, alpha: 1),
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        searchField.font = .systemFont(ofSize: 13)
        searchField.textColor = .white
        searchField.backgroundColor = .clear
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.drawsBackground = false
        searchField.delegate = self
        searchRow.addSubview(searchField)

        searchSpinner = NSProgressIndicator()
        searchSpinner.style = .spinning
        searchSpinner.controlSize = .small
        searchSpinner.isDisplayedWhenStopped = false
        searchRow.addSubview(searchSpinner)

        searchResultsStack = NSStackView()
        searchResultsStack.orientation = .vertical
        searchResultsStack.alignment = .leading
        searchResultsStack.spacing = 4

        searchResultsScroll = NSScrollView()
        searchResultsScroll.documentView = searchResultsStack
        searchResultsScroll.hasVerticalScroller = true
        searchResultsScroll.hasHorizontalScroller = false
        searchResultsScroll.autohidesScrollers = true
        searchResultsScroll.drawsBackground = false
        searchResultsScroll.scrollerStyle = .overlay
        searchPanel.addSubview(searchResultsScroll)

        searchPlaceholder = makeLabel("Type a query and press Enter", size: 12, weight: .regular, color: NotchOverlayConstants.dimText)
        searchPlaceholder.alignment = .center
        searchPanel.addSubview(searchPlaceholder)
    }

    // MARK: Layout

    override func layout() {
        super.layout()

        guard let layer else { return }
        shapeMask.frame = layer.bounds
        shapeMask.path = bezelPath(in: layer.bounds, morph: shapeMorphProgress)

        let width = bounds.width
        let barHeight = NotchOverlayConstants.collapsedHeight(hasNotch: hasNotch)
        let horizontalPadding: CGFloat = 26
        let widthDiff = width - NotchOverlayConstants.collapsedWidth
        let edgeOffset = max(widthDiff / 2, 0)

        // Top bar
        let dotSize: CGFloat = 10
        dotView.frame = NSRect(x: horizontalPadding + edgeOffset, y: (barHeight - dotSize) / 2, width: dotSize, height: dotSize)

        let rightEdge = width - 20 - edgeOffset

        // Search icon replaces the REC label on the right side
        let searchIconSize: CGFloat = 14
        searchIcon.frame = NSRect(
            x: rightEdge - searchIconSize,
            y: (barHeight - searchIconSize) / 2,
            width: searchIconSize,
            height: searchIconSize
        )

        // Timer only visible when expanded (hidden in collapsed bar)
        timerDisplay.sizeToFit()
        timerDisplay.frame.origin = CGPoint(
            x: searchIcon.frame.minX - timerDisplay.frame.width - 8,
            y: (barHeight - timerDisplay.frame.height) / 2
        )

        gearIcon.frame = NSRect(x: width - 20 - edgeOffset + 8, y: (barHeight - 16) / 2, width: 16, height: 16)

        // Panels
        let panelX: CGFloat = 30
        let panelY: CGFloat = barHeight + 14
        let panelWidth = width - panelX * 2
        let panelHeight = max(bounds.height - panelY - 14, 0)

        expandedPanel.frame = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        layoutRecordingRow(panelWidth)

        searchPanel.frame = NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        layoutSearchPanel(panelWidth, panelHeight)
    }

    private func layoutRecordingRow(_ panelWidth: CGFloat) {
        let rowHeight: CGFloat = 46
        timerRow.frame = NSRect(x: 0, y: 0, width: panelWidth, height: rowHeight)

        let inset: CGFloat = 6
        let chipHeight: CGFloat = 32
        let buttonSize: CGFloat = 32
        let buttonGap: CGFloat = 6

        durationLabel.sizeToFit()
        let durationWidth = durationLabel.frame.width + 22
        durationChip.frame = NSRect(x: inset, y: (rowHeight - chipHeight) / 2, width: durationWidth, height: chipHeight)
        durationLabel.frame.origin = CGPoint(x: 11, y: (chipHeight - durationLabel.frame.height) / 2)

        stopChip.isHidden = !isRecording

        let buttonsWidth = isRecording ? (buttonSize * 2 + buttonGap) : buttonSize
        let taskX = inset + durationWidth + 10
        let taskWidth = panelWidth - taskX - inset - buttonsWidth - 10
        taskLabel.frame = NSRect(x: taskX, y: (rowHeight - 20) / 2, width: max(taskWidth, 20), height: 20)

        if isRecording {
            playChip.frame = NSRect(x: panelWidth - inset - buttonSize * 2 - buttonGap, y: (rowHeight - buttonSize) / 2, width: buttonSize, height: buttonSize)
            stopChip.frame = NSRect(x: panelWidth - inset - buttonSize, y: (rowHeight - buttonSize) / 2, width: buttonSize, height: buttonSize)
        } else {
            playChip.frame = NSRect(x: panelWidth - inset - buttonSize, y: (rowHeight - buttonSize) / 2, width: buttonSize, height: buttonSize)
        }

        playIcon.frame = NSRect(x: (buttonSize - 14) / 2, y: (buttonSize - 14) / 2, width: 14, height: 14)
        stopIcon.frame = NSRect(x: (buttonSize - 14) / 2, y: (buttonSize - 14) / 2, width: 14, height: 14)
    }

    private func layoutSearchPanel(_ panelWidth: CGFloat, _ panelHeight: CGFloat) {
        guard !searchPanel.isHidden else { return }

        let rowHeight: CGFloat = 40
        let inset: CGFloat = 16
        let gap: CGFloat = 8

        searchRow.frame = NSRect(x: 0, y: 0, width: panelWidth, height: rowHeight)

        let spinnerSize: CGFloat = 16
        searchSpinner.frame = NSRect(
            x: panelWidth - inset - spinnerSize,
            y: (rowHeight - spinnerSize) / 2,
            width: spinnerSize,
            height: spinnerSize
        )

        let fieldX: CGFloat = inset
        let fieldWidth = panelWidth - fieldX - inset - spinnerSize - 10
        searchField.frame = NSRect(x: fieldX, y: (rowHeight - 20) / 2, width: max(fieldWidth, 40), height: 20)

        let resultsInset: CGFloat = 6
        let resultsY = rowHeight + gap
        let resultsHeight = max(panelHeight - resultsY, 0)
        searchResultsScroll.frame = NSRect(x: resultsInset, y: resultsY, width: panelWidth - resultsInset * 2, height: resultsHeight)

        searchPlaceholder.frame = NSRect(x: 0, y: resultsY + max(resultsHeight / 2 - 10, 0), width: panelWidth, height: 20)
    }

    // MARK: Bezel shape

    private func bezelPath(in rect: CGRect, morph: CGFloat) -> CGPath {
        _ = morph
        let width = rect.width
        let height = rect.height

        let earSize = NotchOverlayConstants.shoulderSize(hasNotch: hasNotch)
        let maxBottomByHeight = max(0, height - earSize - 1)
        let bottomRadius = min(
            NotchOverlayConstants.bottomRadiusLimit(hasNotch: hasNotch),
            height / 2,
            width / 4,
            maxBottomByHeight
        )

        guard width > earSize * 2 + 4, height > earSize + 1 else {
            return CGPath(roundedRect: rect, cornerWidth: min(height / 2, 12), cornerHeight: min(height / 2, 12), transform: nil)
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: earSize, y: earSize), control: CGPoint(x: earSize, y: 0))
        path.addLine(to: CGPoint(x: earSize, y: height - bottomRadius))
        path.addQuadCurve(to: CGPoint(x: earSize + bottomRadius, y: height), control: CGPoint(x: earSize, y: height))
        path.addLine(to: CGPoint(x: width - earSize - bottomRadius, y: height))
        path.addQuadCurve(to: CGPoint(x: width - earSize, y: height - bottomRadius), control: CGPoint(x: width - earSize, y: height))
        path.addLine(to: CGPoint(x: width - earSize, y: earSize))
        path.addQuadCurve(to: CGPoint(x: width, y: 0), control: CGPoint(x: width - earSize, y: 0))
        path.closeSubpath()

        return path
    }

    // MARK: Mouse / Keyboard

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Search icon click — always available
        if searchIcon.frame.insetBy(dx: -6, dy: -6).contains(location) {
            onSearchIconClicked?()
            return
        }

        // If in search mode, only handle search-related clicks
        if isSearchMode {
            let fieldFrame = searchField.convert(searchField.bounds, to: self)
            if fieldFrame.contains(location) {
                window?.makeFirstResponder(searchField)
            }
            return
        }

        // Recording controls
        if dotView.frame.insetBy(dx: -5, dy: -5).contains(location) {
            onToggleRecording?()
            return
        }

        if timerDisplay.frame.insetBy(dx: -5, dy: -5).contains(location) {
            onToggleRecording?()
            return
        }

        let taskFrame = taskLabel.convert(taskLabel.bounds, to: self)
        if taskFrame.contains(location) {
            taskLabel.isEditable = true
            taskLabel.isSelectable = true
            window?.makeFirstResponder(taskLabel)
            return
        }

        if taskLabel.isEditable {
            endTaskEditing()
        }

        let playFrame = playChip.convert(playChip.bounds, to: self)
        if playFrame.contains(location) {
            onToggleRecording?()
            return
        }

        let stopFrame = stopChip.convert(stopChip.bounds, to: self)
        if !stopChip.isHidden && stopFrame.contains(location) {
            if isRecording { onToggleRecording?() }
            return
        }

        super.mouseDown(with: event)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            if control === searchField {
                let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    onSearchSubmitted?(query)
                }
                return true
            }
            endTaskEditing()
            return true
        }
        if commandSelector == #selector(cancelOperation(_:)) {
            if isSearchMode {
                onSearchIconClicked?()  // toggle out of search
                return true
            }
        }
        return false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === taskLabel else { return }
        onSessionNoteChanged?(taskLabel.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === taskLabel else { return }
        onSessionNoteChanged?(taskLabel.stringValue)
    }

    private func endTaskEditing() {
        taskLabel.isEditable = false
        taskLabel.isSelectable = false
        window?.makeFirstResponder(nil)
        onSessionNoteChanged?(taskLabel.stringValue)
    }

    // MARK: Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let timerTrackingArea { removeTrackingArea(timerTrackingArea) }

        let timerFrame = timerDisplay.frame.insetBy(dx: -5, dy: -5)
        timerTrackingArea = NSTrackingArea(
            rect: timerFrame,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["element": "timer"]
        )
        if let timerTrackingArea { addTrackingArea(timerTrackingArea) }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo as? [String: String],
              info["element"] == "timer" else { return }
        timerHovered = true
        updateTimerDisplay()
    }

    override func mouseExited(with event: NSEvent) {
        guard let info = event.trackingArea?.userInfo as? [String: String],
              info["element"] == "timer" else { return }
        timerHovered = false
        updateTimerDisplay()
    }

    // MARK: State updates

    func update(recording: Bool) {
        if recording && !isRecording {
            recordingStartedAt = Date()
            startElapsedTimer()
        } else if !recording && isRecording {
            stopElapsedTimer()
            recordingStartedAt = nil
        }
        isRecording = recording
        updateDotAppearance()
        updateTimerDisplay()
        updatePlayIcon()
        needsLayout = true
    }

    /// Show the recording panel (normal hover-expand)
    func showRecordingContent() {
        guard !isSearchMode else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchOverlayConstants.expandDuration
            expandedPanel.animator().alphaValue = 1
            gearIcon.animator().alphaValue = 1
            timerDisplay.animator().alphaValue = 1
        }
    }

    /// Hide the recording panel (normal collapse)
    func hideRecordingContent(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchOverlayConstants.collapseDuration
            expandedPanel.animator().alphaValue = 0
            gearIcon.animator().alphaValue = 0
            timerDisplay.animator().alphaValue = 0
        }, completionHandler: completion)
    }

    /// Enter search mode — called AFTER the window has expanded to search size
    func enterSearchMode() {
        guard !isSearchMode else { return }
        isSearchMode = true

        searchField.stringValue = ""
        clearSearchResults()
        searchPlaceholder.stringValue = "Type a query and press Enter"
        searchPlaceholder.isHidden = false
        searchPanel.isHidden = false

        // Crossfade: hide recording panel, show search panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            expandedPanel.animator().alphaValue = 0
            gearIcon.animator().alphaValue = 0
            searchPanel.animator().alphaValue = 1
        }

        searchIcon.contentTintColor = .white

        // Focus search field after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.isSearchMode else { return }
            self.window?.makeFirstResponder(self.searchField)
        }
    }

    /// Exit search mode — resets state, hides search panel. Does NOT trigger animations on the window.
    func exitSearchMode() {
        guard isSearchMode else { return }
        isSearchMode = false

        searchField.stringValue = ""
        window?.makeFirstResponder(nil)
        searchIcon.contentTintColor = NotchOverlayConstants.dimText

        // Hide search panel immediately
        searchPanel.alphaValue = 0
        searchPanel.isHidden = true
        expandedPanel.alphaValue = 0
        gearIcon.alphaValue = 0
    }

    // MARK: Search results

    func showSearchLoading() {
        searchSpinner.startAnimation(nil)
        searchPlaceholder.stringValue = "Searching…"
        searchPlaceholder.isHidden = false
        clearSearchResults()
    }

    func showSearchResults(_ results: [ActivitySearchResult]) {
        searchSpinner.stopAnimation(nil)
        clearSearchResults()

        if results.isEmpty {
            searchPlaceholder.stringValue = "No results found"
            searchPlaceholder.isHidden = false
            return
        }

        searchPlaceholder.isHidden = true

        for result in results.prefix(20) {
            let row = buildResultRow(result)
            searchResultsStack.addArrangedSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.leadingAnchor.constraint(equalTo: searchResultsStack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: searchResultsStack.trailingAnchor).isActive = true
        }
    }

    private func clearSearchResults() {
        for view in searchResultsStack.arrangedSubviews {
            searchResultsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func buildResultRow(_ result: ActivitySearchResult) -> NSView {
        let row = FlippedView()
        row.wantsLayer = true
        row.layer?.backgroundColor = NotchOverlayConstants.chipColor.cgColor
        row.layer?.cornerRadius = 8

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: result.timestamp)
        let appStr = result.appName ?? ""

        let header = makeLabel("\(timeStr)  \(appStr)", size: 11, weight: .semibold, color: NSColor(white: 0.7, alpha: 1))
        header.lineBreakMode = .byTruncatingTail
        row.addSubview(header)

        let body = makeLabel(result.activity, size: 11, weight: .regular, color: NSColor(white: 0.85, alpha: 1))
        body.lineBreakMode = .byTruncatingTail
        body.maximumNumberOfLines = 2
        body.cell?.wraps = true
        body.cell?.isScrollable = false
        row.addSubview(body)

        header.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            body.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            body.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            body.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -6),
        ])

        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return row
    }

    // MARK: Private helpers

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimerDisplay()
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateDotAppearance() {
        let color: NSColor = isRecording
            ? NSColor(red: 0.91, green: 0.45, blue: 0.32, alpha: 1.0)
            : NSColor(white: 0.5, alpha: 1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            dotView.layer?.backgroundColor = color.cgColor
        }
    }

    private func updateTimerDisplay() {
        if timerHovered {
            timerDisplay.stringValue = isRecording ? "⏸" : "▶"
            timerDisplay.sizeToFit()
            needsLayout = true
            return
        }
        guard isRecording, let recordingStartedAt else {
            timerDisplay.stringValue = "REC"
            timerDisplay.sizeToFit()
            needsLayout = true
            return
        }
        let elapsed = Int(Date().timeIntervalSince(recordingStartedAt))
        timerDisplay.stringValue = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        timerDisplay.sizeToFit()
        needsLayout = true
    }

    private func updatePlayIcon() {
        let symbolName = isRecording ? "pause.fill" : "record.circle.fill"
        if let image = sfImage(symbolName, size: 12, weight: .medium) {
            playIcon.image = image
        }
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        return label
    }

    private func roundedBox(_ color: NSColor, radius: CGFloat) -> NSView {
        let view = FlippedView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = radius
        return view
    }

    private func sfImage(_ name: String, size: CGFloat, weight: NSFont.Weight) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    func applyDisplayProfile(hasNotch: Bool) {
        guard self.hasNotch != hasNotch else { return }
        self.hasNotch = hasNotch
        needsLayout = true
    }
}

// MARK: - Animation Controller

private final class NotchOverlayAnimationController {
    private let window: NotchOverlayWindow
    private weak var contentView: NotchOverlayContentView?

    private(set) var info: NotchOverlayInfo
    private(set) var isExpanded = false
    private(set) var isSearchExpanded = false
    private var isAnimating = false

    init(window: NotchOverlayWindow, info: NotchOverlayInfo, contentView: NotchOverlayContentView) {
        self.window = window
        self.info = info
        self.contentView = contentView
    }

    func updateInfo(_ info: NotchOverlayInfo) { self.info = info }

    func animateOpen(completion: (() -> Void)? = nil) {
        let start = notchFrame()
        let target = collapsedFrame()

        contentView?.shapeMorphProgress = 0
        window.setFrame(start, display: false)
        window.orderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NotchOverlayConstants.openDuration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                self.window.animator().setFrame(target, display: true)
                self.contentView?.animator().shapeMorphProgress = 1
            }, completionHandler: {
                self.contentView?.shapeMorphProgress = 1
                completion?()
            })
        }
    }

    func expand(completion: (() -> Void)? = nil) {
        guard !isExpanded, !isAnimating else { return }
        isAnimating = true
        isExpanded = true
        animateTo(expandedFrame(), completion: completion)
    }

    func collapse(completion: (() -> Void)? = nil) {
        guard isExpanded, !isAnimating else { return }
        isAnimating = true
        isExpanded = false
        isSearchExpanded = false
        animateTo(collapsedFrame(), completion: completion)
    }

    func expandToSearch(completion: (() -> Void)? = nil) {
        guard !isAnimating else { return }
        isAnimating = true
        isExpanded = true
        isSearchExpanded = true
        animateTo(searchExpandedFrame(), completion: completion)
    }

    func collapseFromSearch(completion: (() -> Void)? = nil) {
        guard !isAnimating else { return }
        isAnimating = true
        isExpanded = false
        isSearchExpanded = false
        animateTo(collapsedFrame(), completion: completion)
    }

    private func animateTo(_ frame: NSRect, completion: (() -> Void)?) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchOverlayConstants.expandDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
            completion?()
        })
    }

    func notchFrame() -> NSRect {
        let width = info.notchWidth + 10
        let height: CGFloat = 32
        return NSRect(x: info.centerX - width / 2, y: info.topY - height, width: width, height: height)
    }

    func collapsedFrame() -> NSRect {
        let width = NotchOverlayConstants.collapsedWidth
        let height = NotchOverlayConstants.collapsedHeight(hasNotch: info.hasNotch)
        return NSRect(x: info.centerX - width / 2, y: info.topY - height, width: width, height: height)
    }

    func expandedFrame() -> NSRect {
        let width = NotchOverlayConstants.expandedWidth
        let height = NotchOverlayConstants.expandedHeight
        return NSRect(x: info.centerX - width / 2, y: info.topY - height, width: width, height: height)
    }

    func searchExpandedFrame() -> NSRect {
        let width = NotchOverlayConstants.searchExpandedWidth
        let height = NotchOverlayConstants.searchExpandedHeight
        return NSRect(x: info.centerX - width / 2, y: info.topY - height, width: width, height: height)
    }

    /// The current reference frame for hit-testing mouse proximity
    func currentFrame() -> NSRect {
        if isSearchExpanded { return searchExpandedFrame() }
        if isExpanded { return expandedFrame() }
        return collapsedFrame()
    }
}

// MARK: - Controller

@MainActor
final class NotchOverlayController {
    private let window: NotchOverlayWindow
    private let contentView: NotchOverlayContentView
    private let animationController: NotchOverlayAnimationController

    private var recordingSub: AnyCancellable?
    private var screenObserver: NSObjectProtocol?

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var debounceTimer: Timer?
    private var dwellTimer: Timer?
    private var isInExpandZone = false

    init() {
        let info = NotchOverlayDetector.detect()

        window = NotchOverlayWindow(contentRect: .zero)
        contentView = NotchOverlayContentView()
        animationController = NotchOverlayAnimationController(window: window, info: info, contentView: contentView)

        window.setFrame(animationController.notchFrame(), display: false)
        contentView.frame = window.contentView?.bounds ?? .zero
        contentView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(contentView)
        contentView.applyDisplayProfile(hasNotch: info.hasNotch)

        // Wire callbacks
        contentView.onToggleRecording = {
            AppState.shared.isRecording.toggle()
        }
        contentView.onSessionNoteChanged = { note in
            AppState.shared.sessionNoteDraft = note
        }
        contentView.onSearchIconClicked = { [weak self] in
            self?.toggleSearch()
        }
        contentView.onSearchSubmitted = { [weak self] query in
            self?.performSearch(query)
        }
        contentView.update(recording: AppState.shared.isRecording)

        recordingSub = AppState.shared.$isRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.contentView.update(recording: isRecording)
            }

        setupScreenObserver()
        setupMouseMonitoring()
        animationController.animateOpen()
    }

    // MARK: Search

    private func toggleSearch() {
        if contentView.isSearchMode {
            // Exit search → collapse
            contentView.exitSearchMode()
            animationController.collapseFromSearch()
        } else {
            // Enter search → expand to search size, then enter search mode
            animationController.expandToSearch { [weak self] in
                self?.contentView.enterSearchMode()
            }
        }
    }

    private func performSearch(_ query: String) {
        contentView.showSearchLoading()
        Task {
            let results = await ActivityAgentManager.shared.searchFTS(query)
            await MainActor.run { [weak self] in
                self?.contentView.showSearchResults(results)
            }
        }
    }

    // MARK: Teardown

    func tearDown() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        dwellTimer?.invalidate()
        dwellTimer = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        recordingSub?.cancel()
        recordingSub = nil

        window.orderOut(nil)
        window.close()
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        debounceTimer?.invalidate()
        dwellTimer?.invalidate()
    }

    // MARK: Screen observer

    private func setupScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let updatedInfo = NotchOverlayDetector.detect()
            self.animationController.updateInfo(updatedInfo)
            self.contentView.applyDisplayProfile(hasNotch: updatedInfo.hasNotch)
            self.window.setFrame(self.animationController.currentFrame(), display: true)
        }
    }

    // MARK: Mouse monitoring

    private func setupMouseMonitoring() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMoved()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
    }

    private func handleMouseMoved() {
        let mouse = NSEvent.mouseLocation
        let referenceFrame = animationController.currentFrame()

        let fullZone = referenceFrame.insetBy(dx: -NotchOverlayConstants.hoverPadding, dy: -NotchOverlayConstants.hoverPadding)
        let nearFullZone = fullZone.contains(mouse)

        let edgeWidth: CGFloat = 60
        let middleZone = NSRect(
            x: referenceFrame.minX + edgeWidth - NotchOverlayConstants.hoverPadding,
            y: referenceFrame.minY - NotchOverlayConstants.hoverPadding,
            width: referenceFrame.width - edgeWidth * 2 + NotchOverlayConstants.hoverPadding * 2,
            height: referenceFrame.height + NotchOverlayConstants.hoverPadding * 2
        )
        let inMiddleZone = middleZone.contains(mouse)

        let collapsedFrame = animationController.collapsedFrame()
        let topThreshold = collapsedFrame.maxY - (collapsedFrame.height * 0.05)
        let nearTop = mouse.y >= topThreshold

        let shouldExpand = inMiddleZone && nearTop

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: NotchOverlayConstants.debounceInterval, repeats: false) { [weak self] _ in
            guard let self else { return }

            // Don't auto-expand while in search mode
            if shouldExpand && !self.isInExpandZone && !self.contentView.isSearchMode {
                self.isInExpandZone = true
                self.dwellTimer?.invalidate()
                self.dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    guard let self, self.isInExpandZone else { return }
                    self.expandNotch()
                }
            } else if !shouldExpand && self.isInExpandZone {
                self.isInExpandZone = false
                self.dwellTimer?.invalidate()
            }

            // Mouse left the area entirely — collapse
            if !nearFullZone {
                self.isInExpandZone = false
                self.dwellTimer?.invalidate()
                if self.contentView.isSearchMode {
                    self.contentView.exitSearchMode()
                    self.animationController.collapseFromSearch()
                } else {
                    self.collapseNotch()
                }
            }
        }
    }

    private func expandNotch() {
        contentView.showRecordingContent()
        animationController.expand()
    }

    private func collapseNotch() {
        contentView.hideRecordingContent()
        animationController.collapse()
    }
}
