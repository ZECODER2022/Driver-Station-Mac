//
//  DriverStation.swift
//  The view-model that owns control state, the UDP link, joysticks and console,
//  and enforces the Driver Station's safety rules.
//
//  Threading: all @Published mutations happen on the main thread. The UDP link's
//  callbacks arrive on a background queue and are hopped to main here.
//

import Foundation
import Combine

final class DriverStation: ObservableObject {

    // MARK: Connection settings
    @Published var teamNumberText: String = "0"
    @Published var addressOverride: String = ""

    // MARK: Control state
    @Published var mode: ControlMode = .teleoperated { didSet { pushControl() } }
    @Published var alliance: AllianceStation = .red1 { didSet { pushControl() } }
    @Published private(set) var enabled: Bool = false
    @Published private(set) var isEStopped: Bool = false

    // MARK: Robot status (derived from incoming packets)
    @Published private(set) var robotComms: Bool = false
    @Published private(set) var robotCode: Bool = false
    @Published private(set) var brownout: Bool = false
    @Published private(set) var voltage: Double = 0
    @Published private(set) var resolvedAddress: String = "—"
    @Published private(set) var packetsSent: UInt64 = 0
    @Published private(set) var packetsReceived: UInt64 = 0
    @Published private(set) var lastStatus: RobotStatus?

    // MARK: Subsystems
    let joysticks = JoystickManager()
    let console = ConsoleListener()
    private let link = UDPLink()
    private var uiTimer: Timer?

    private var teamNumber: Int {
        Int(teamNumberText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    /// When set via FRC_DS_DEBUG=1, parsed status packets are logged to stderr.
    private let debugLogging = ProcessInfo.processInfo.environment["FRC_DS_DEBUG"] == "1"

    /// True when it is safe to enable: comms up, code running, not e-stopped.
    var canEnable: Bool { robotComms && robotCode && !isEStopped && !enabled }

    // MARK: Init

    init() {
        link.joystickProvider = { [weak self] in
            self?.joysticks.currentStates() ?? []
        }
        link.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.handleStatus(status) }
        }
        // Optional pre-configuration (handy for WPILib simulation on 127.0.0.1).
        let env = ProcessInfo.processInfo.environment
        if let team = env["FRC_DS_TEAM"] { teamNumberText = team }
        if let address = env["FRC_DS_ADDRESS"] { addressOverride = address }

        link.start()
        console.start()

        updateHost()
        pushControl()

        uiTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tickUI()
        }
    }

    // MARK: Commands

    func enable() {
        guard canEnable else { return }
        enabled = true
        pushControl()
    }

    func disable() {
        enabled = false
        pushControl()
    }

    /// Latching emergency stop. The robot stays e-stopped until it is rebooted;
    /// `clearEStop()` only resets the Driver Station's own latch.
    func emergencyStop() {
        isEStopped = true
        enabled = false
        pushControl()
    }

    func clearEStop() {
        isEStopped = false
        pushControl()
    }

    func rebootRoboRIO() { link.pulseReboot() }
    func restartRobotCode() { link.pulseRestartCode() }

    /// Re-resolves the robot host from the team number or address override.
    func applyConnectionSettings() { updateHost() }

    // MARK: Internals

    private func updateHost() {
        let override = addressOverride.trimmingCharacters(in: .whitespaces)
        let host: String?
        if !override.isEmpty {
            host = override
        } else if let ip = RobotAddress.ip(forTeam: teamNumber) {
            host = ip
        } else {
            host = nil
        }
        resolvedAddress = host ?? "—"
        link.setHost(host)
    }

    private func pushControl() {
        var c = ControlSnapshot()
        c.mode = mode
        c.enabled = enabled
        c.eStop = isEStopped
        c.alliance = alliance
        link.setControl(c)
    }

    private func handleStatus(_ status: RobotStatus) {
        lastStatus = status
        robotCode = status.robotCodePresent
        brownout = status.brownout
        voltage = status.voltage
        if status.eStop && !isEStopped {
            emergencyStop()
        }
        if debugLogging {
            let line = "RX seq=\(status.sequence) volts=\(String(format: "%.2f", status.voltage)) " +
                       "code=\(status.robotCodePresent ? 1 : 0) enabled=\(status.enabled ? 1 : 0) " +
                       "mode=\(status.mode.rawValue)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    private func tickUI() {
        // Comms is "up" if we received a status packet in the last second.
        let up = Date().timeIntervalSince(link.lastReceive) < 1.0
        if up != robotComms { robotComms = up }

        if !up {
            // Mirror the real DS: losing comms drops code/voltage and disables.
            if robotCode { robotCode = false }
            if voltage != 0 { voltage = 0 }
            if enabled { disable() }
        }

        packetsSent = link.sentCount
        packetsReceived = link.receivedCount
        joysticks.refreshUI()
    }
}
