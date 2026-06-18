//
//  main.swift
//  Entry point. Runs the protocol self-test when invoked with `--selftest`,
//  otherwise launches the SwiftUI application.
//

import Foundation

if CommandLine.arguments.contains("--selftest") {
    exit(runSelfTest() ? 0 : 1)
}

FRCDriverStationApp.main()
