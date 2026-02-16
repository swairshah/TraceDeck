//
//  TraceDeckApp.swift
//  TraceDeck
//

import SwiftUI

@main
struct TraceDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window(AppIdentity.displayName, id: "main") {
            MainView()
                .frame(minWidth: 800, minHeight: 500)
                .onDisappear {
                    // Hide from dock when window is closed
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1000, height: 600)
        .commands {
            // Remove "New Window" command
            CommandGroup(replacing: .newItem) { }
        }
    }
}
