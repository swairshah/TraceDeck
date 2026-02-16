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
    private var recordingSub: AnyCancellable?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = 34

        if let button = statusItem.button {
            updateIcon(isRecording: AppState.shared.isRecording)
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: StatusMenuView())

        // Observe recording state
        recordingSub = AppState.shared.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.updateIcon(isRecording: isRecording)
            }
    }

    private func updateIcon(isRecording: Bool) {
        if let button = statusItem.button {
            let image = NSImage(named: menuBarIconAssetName) ?? NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            let targetWidth: CGFloat = 30
            let iconAspectRatio: CGFloat = {
                guard let rep = image?.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) else {
                    return 1.8
                }
                return CGFloat(rep.pixelsWide) / CGFloat(rep.pixelsHigh)
            }()
            let targetHeight = max(15, min(22, targetWidth / iconAspectRatio))
            image?.size = NSSize(width: targetWidth, height: targetHeight)
            button.image = image
            button.imageScaling = .scaleProportionallyUpOrDown
            button.contentTintColor = nil
            button.alphaValue = isRecording ? 1.0 : 0.92
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Activate app to ensure popover gets focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
