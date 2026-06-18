//
//  FRCDriverStationApp.swift
//  SwiftUI application scene.
//

import SwiftUI

struct FRCDriverStationApp: App {
    @StateObject private var ds = DriverStation()

    var body: some Scene {
        WindowGroup("FRC Driver Station") {
            ContentView()
                .environmentObject(ds)
                .frame(minWidth: 860, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}
