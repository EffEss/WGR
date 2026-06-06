//
//  iDrizzleWatchApp.swift
//  iDrizzleWatch Watch App
//
//  Created by Dino Hopic on 5/31/26.
//

import SwiftUI

@main
struct iDrizzleWatch_Watch_AppApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundedAt: Date?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background, .inactive:
                        backgroundedAt = Date()
                    case .active:
                        if let backgroundedAt {
                            RadarService.shared.handleForegroundResumed(after: Date().timeIntervalSince(backgroundedAt))
                            self.backgroundedAt = nil
                        }
                    @unknown default:
                        break
                    }
                }
        }
    }
}
