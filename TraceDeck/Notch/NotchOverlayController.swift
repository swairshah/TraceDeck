//
//  NotchOverlayController.swift
//  TraceDeck
//

import AppKit
import Combine
import QuartzCore

private enum NotchOverlayConstants {
    static let collapsedWidth: CGFloat = 300
    static let collapsedHeight: CGFloat = 36
    static let expandedWidth: CGFloat = 360
    static let expandedHeight: CGFloat = 120

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
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class NotchOverlayContentView: NSView, NSTextFieldDelegate {
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var onToggleRecording: (() -> Void)?

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

    private var dotView: NSView!
    private var timerDisplay: NSTextField!
    private var timerHovered = false
    private var timerTrackingArea: NSTrackingArea?

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

    private var isRecording = false
    private var recordingStartedAt: Date?
    private var elapsedTimer: Timer?

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

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        shapeMask.fillColor = NSColor.white.cgColor
        layer?.mask = shapeMask

        buildTopBar()
        buildExpandedPanel()
        update(recording: AppState.shared.isRecording)
    }

    private func buildTopBar() {
        dotView = NSView()
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 5
        addSubview(dotView)

        timerDisplay = makeLabel("REC", size: 11, weight: .medium)
        timerDisplay.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        addSubview(timerDisplay)
    }

    private func buildExpandedPanel() {
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

        buildControlRow()
    }

    private func buildControlRow() {
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

    override func layout() {
        super.layout()

        guard let layer else { return }
        shapeMask.frame = layer.bounds
        shapeMask.path = bezelPath(in: layer.bounds, morph: shapeMorphProgress)

        let width = bounds.width
        let barHeight: CGFloat = NotchOverlayConstants.collapsedHeight
        let horizontalPadding: CGFloat = 26
        let widthDiff = width - NotchOverlayConstants.collapsedWidth
        let edgeOffset = widthDiff / 2

        let dotSize: CGFloat = 10
        dotView.frame = NSRect(x: horizontalPadding + edgeOffset, y: (barHeight - dotSize) / 2, width: dotSize, height: dotSize)

        timerDisplay.sizeToFit()
        timerDisplay.frame.origin = CGPoint(
            x: width - timerDisplay.frame.width - 20 - edgeOffset,
            y: (barHeight - timerDisplay.frame.height) / 2
        )

        let panelX: CGFloat = 28
        let panelY: CGFloat = barHeight + 18

        gearIcon.frame = NSRect(x: width - 20 - edgeOffset + 8, y: (barHeight - 16) / 2, width: 16, height: 16)

        let panelWidth = width - panelX * 2
        expandedPanel.frame = NSRect(x: panelX, y: panelY, width: panelWidth, height: bounds.height - panelY - 12)
        layoutControlRow(panelWidth)
    }

    private func layoutControlRow(_ panelWidth: CGFloat) {
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

    private func bezelPath(in rect: CGRect, morph: CGFloat) -> CGPath {
        _ = morph
        let width = rect.width
        let height = rect.height

        let earSize: CGFloat = 16
        let bottomRadius: CGFloat = min(22, height / 2, width / 4)

        guard width > earSize * 2 + 4, height > earSize + bottomRadius else {
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

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

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
            endTaskEditing()
            return true
        }
        return false
    }

    private func endTaskEditing() {
        taskLabel.isEditable = false
        taskLabel.isSelectable = false
        window?.makeFirstResponder(nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let timerTrackingArea {
            removeTrackingArea(timerTrackingArea)
        }

        let timerFrame = timerDisplay.frame.insetBy(dx: -5, dy: -5)
        timerTrackingArea = NSTrackingArea(
            rect: timerFrame,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: ["element": "timer"]
        )

        if let timerTrackingArea {
            addTrackingArea(timerTrackingArea)
        }
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

    func showContent() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchOverlayConstants.expandDuration
            expandedPanel.animator().alphaValue = 1
            gearIcon.animator().alphaValue = 1
        }
    }

    func hideContent(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchOverlayConstants.collapseDuration
            expandedPanel.animator().alphaValue = 0
            gearIcon.animator().alphaValue = 0
        }, completionHandler: completion)
    }

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
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        timerDisplay.stringValue = String(format: "%d:%02d", minutes, seconds)
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
}

private final class NotchOverlayAnimationController {
    private let window: NotchOverlayWindow
    private weak var contentView: NotchOverlayContentView?

    private(set) var info: NotchOverlayInfo
    private(set) var isExpanded = false
    private var isAnimating = false

    init(window: NotchOverlayWindow, info: NotchOverlayInfo, contentView: NotchOverlayContentView) {
        self.window = window
        self.info = info
        self.contentView = contentView
    }

    func updateInfo(_ info: NotchOverlayInfo) {
        self.info = info
    }

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

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchOverlayConstants.expandDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(expandedFrame(), display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
            completion?()
        })
    }

    func collapse(completion: (() -> Void)? = nil) {
        guard isExpanded, !isAnimating else { return }
        isAnimating = true
        isExpanded = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NotchOverlayConstants.collapseDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.0, 0.0, 0.2, 1.0)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(collapsedFrame(), display: true)
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
        let height = NotchOverlayConstants.collapsedHeight
        return NSRect(x: info.centerX - width / 2, y: info.topY - height, width: width, height: height)
    }

    func expandedFrame() -> NSRect {
        let width = NotchOverlayConstants.expandedWidth
        let height = NotchOverlayConstants.expandedHeight
        return NSRect(x: info.centerX - width / 2, y: info.topY - height, width: width, height: height)
    }
}

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

        contentView.onToggleRecording = {
            AppState.shared.isRecording.toggle()
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

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        debounceTimer?.invalidate()
        dwellTimer?.invalidate()
    }

    private func setupScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let updatedInfo = NotchOverlayDetector.detect()
            self.animationController.updateInfo(updatedInfo)
            let frame = self.animationController.isExpanded
                ? self.animationController.expandedFrame()
                : self.animationController.collapsedFrame()
            self.window.setFrame(frame, display: true)
        }
    }

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
        let referenceFrame = animationController.isExpanded
            ? animationController.expandedFrame()
            : animationController.collapsedFrame()

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

            if shouldExpand && !self.isInExpandZone {
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

            if !nearFullZone {
                self.isInExpandZone = false
                self.dwellTimer?.invalidate()
                self.collapseNotch()
            }
        }
    }

    private func expandNotch() {
        contentView.showContent()
        animationController.expand()
    }

    private func collapseNotch() {
        contentView.hideContent()
        animationController.collapse()
    }
}
