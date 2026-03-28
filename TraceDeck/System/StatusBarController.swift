//
//  StatusBarController.swift
//  TraceDeck
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController {
    // Toggle this asset name to quickly compare menubar icon variants.
    private let menuBarIconAssetName = "MenuBarIconOption1"
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    /// Called on right-click of the menu bar icon.
    var onRightClick: (() -> Void)?

    // MARK: - Icon state

    private var isRecording = false
    private var isIndexing = false
    private var isFlashing = false
    private var flashTimer: Timer?

    // Icon colors (faded versions of the app icon colors)
    private let recordingColor = NSColor(red: 0.85, green: 0.40, blue: 0.22, alpha: 1.0)   // burnt orange
    private let flashColor     = NSColor(red: 0.98, green: 0.45, blue: 0.20, alpha: 1.0)   // brighter on flash
    private let indexingColor  = NSColor(red: 0.88, green: 0.76, blue: 0.25, alpha: 1.0)   // ochre/gold, brighter

    // Circle geometry as fractions of the 48×48 source image (from pixel analysis)
    // Left circle: center (12, 22), radius 13  →  fractions of 48
    // Right circle: center (34, 23), radius 13
    private let leftCircle  = (cx: 0.250, cy: 0.458, r: 0.271)
    private let rightCircle = (cx: 0.708, cy: 0.479, r: 0.271)

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = 34

        if let button = statusItem.button {
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleClick(_:))
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: StatusMenuView())

        // Observe recording state
        AppState.shared.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.isRecording = recording
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        // Observe indexing state
        ActivityAgentManager.shared.$isIndexing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] indexing in
                self?.isIndexing = indexing
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        // Observe screenshot captures for flash effect
        NotificationCenter.default.publisher(for: .screenshotCaptured)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.flashCaptureIndicator()
            }
            .store(in: &cancellables)

        // Initial icon
        isRecording = AppState.shared.isRecording
        refreshIcon()
    }

    // MARK: - Icon rendering

    private func refreshIcon() {
        guard let button = statusItem.button else { return }

        let baseImage = NSImage(named: menuBarIconAssetName) ?? NSImage(named: "MenuBarIcon")
        guard let base = baseImage else { return }

        let targetWidth: CGFloat = 30
        let iconAspectRatio: CGFloat = {
            guard let rep = base.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) else {
                return 1.8
            }
            return CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh)
        }()
        let targetHeight = max(15, min(22, targetWidth / iconAspectRatio))
        let targetSize = NSSize(width: targetWidth, height: targetHeight)

        let needsColor = isRecording || isIndexing || isFlashing

        if needsColor {
            let colored = createColoredIcon(base: base, size: targetSize)
            button.image = colored
        } else {
            base.isTemplate = true
            base.size = targetSize
            button.image = base
        }

        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = nil
        button.alphaValue = isRecording ? 1.0 : 0.92
    }

    private func createColoredIcon(base: NSImage, size: NSSize) -> NSImage {
        // Strap boundary (fraction of width) — col 23 of 48 is the 1px strap
        let strapLeft: CGFloat  = 0.47   // clip left circle before this
        let strapRight: CGFloat = 0.49   // clip right circle after this

        let result = NSImage(size: size, flipped: false) { [self] rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // 1. Draw the base icon twice to boost alpha
            //    (right circle has mostly alpha 100-150, which makes colors faint)
            base.size = size
            base.draw(in: rect)
            ctx.setBlendMode(.normal)
            base.draw(in: rect)

            // 2. Recolor entire icon to menu bar foreground using .sourceIn
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(menuBarForeground.cgColor)
            ctx.fill(rect)

            // 3. Color the left circle, clipped to avoid the strap
            if isRecording || isFlashing {
                let color = isFlashing ? flashColor : recordingColor
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 0, width: rect.width * strapLeft, height: rect.height))
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: circleRect(leftCircle, in: rect))
                ctx.restoreGState()
            }

            // 4. Color the right circle, clipped to avoid the strap
            if isIndexing {
                let clipX = rect.width * strapRight
                ctx.saveGState()
                ctx.clip(to: CGRect(x: clipX, y: 0, width: rect.width - clipX, height: rect.height))
                ctx.setFillColor(indexingColor.cgColor)
                ctx.fillEllipse(in: circleRect(rightCircle, in: rect))
                ctx.restoreGState()
            }

            return true
        }

        result.isTemplate = false
        return result
    }

    /// Map fractional circle geometry (from 48×48 source image) to a drawing rect.
    /// Handles y-flip for non-flipped coordinate system.
    private func circleRect(_ circle: (cx: Double, cy: Double, r: Double), in rect: CGRect) -> CGRect {
        let cx = circle.cx * rect.width
        let cy = (1.0 - circle.cy) * rect.height
        let rx = circle.r * rect.width
        let ry = circle.r * rect.height
        return CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)
    }

    /// Appropriate foreground color for the current menu bar appearance.
    private var menuBarForeground: NSColor {
        guard let button = statusItem.button else { return .white }
        let appearance = button.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .white : .black
    }

    // MARK: - Flash effect

    private func flashCaptureIndicator() {
        isFlashing = true
        refreshIcon()

        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isFlashing = false
                self?.refreshIcon()
            }
        }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .rightMouseUp:
            onRightClick?()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Activate app to ensure popover gets focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
