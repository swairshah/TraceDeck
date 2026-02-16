//
//  Shortcuts.swift
//  TraceDeck
//
//  Global keyboard shortcut definitions using KeyboardShortcuts library.
//

import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Trigger a manual screenshot capture
    static let captureNow = Self("captureNow", default: .init(.s, modifiers: [.option, .shift]))

    /// Toggle recording on/off
    static let toggleRecording = Self("toggleRecording", default: .init(.space, modifiers: [.option]))
}
