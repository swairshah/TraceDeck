//
//  AppIdentity.swift
//  TraceDeck
//

import Foundation

enum AppIdentity {
    static let displayName = "TraceDeck"
    private static let appSupportFolderName = "tracedeck"
    private static let legacyAppSupportFolderNames = ["TraceDeck", "ctxl", "Monitome"]

    static func appSupportBaseURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let preferredURL = appSupport.appendingPathComponent(appSupportFolderName, isDirectory: true)
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        for legacyName in legacyAppSupportFolderNames {
            let legacyURL = appSupport.appendingPathComponent(legacyName, isDirectory: true)
            if fileManager.fileExists(atPath: legacyURL.path) {
                do {
                    try fileManager.moveItem(at: legacyURL, to: preferredURL)
                    return preferredURL
                } catch {
                    print("AppIdentity: failed to migrate app support directory: \(error)")
                    return legacyURL
                }
            }
        }

        try? fileManager.createDirectory(at: preferredURL, withIntermediateDirectories: true)
        return preferredURL
    }
}
