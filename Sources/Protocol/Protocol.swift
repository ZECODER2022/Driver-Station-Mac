//
//  Protocol.swift
//  FRC Driver Station for macOS
//
//  Wire-protocol implementation for the FRC Driver Station <-> roboRIO link.
//
//  Reference: the reverse-engineered FRC communication protocol
//  (https://frcture.readthedocs.io/en/latest/driverstation/).
//
//  Summary of the two UDP datagrams:
//
//  DS  -> RIO  (UDP port 1110, sent every 20 ms):
//      [0..1] sequence number (uint16, big-endian, increments each packet)
//      [2]    comm version = 0x01
//      [3]    control byte   (0x80 e-stop | 0x08 fms | 0x04 enabled | 0x03 mode)
//      [4]    request byte   (0x08 reboot | 0x04 restart-code)
//      [5]    alliance       (0..2 = Red 1..3, 3..5 = Blue 1..3)
//      [6..]  tags (0x0C joystick, ...)
//
//  RIO -> DS   (UDP port 1150):
//      [0..1] sequence echo
//      [2]    comm version
//      [3]    status byte    (0x80 estop | 0x10 brownout | 0x08 code-init | 0x04 enabled | 0x03 mode)
//      [4]    trace byte     (bit5 robot-code | bit4 is-roboRIO)
//      [5..6] battery voltage (volts = byte[5] + byte[6] / 256)
//      [7]    request date/time (0x01 = robot wants the DS to send date/tz tags)
//      [8..]  tags
//

import Foundation

// MARK: - Control mode

/// The three robot run modes selectable on the Driver Station.
enum ControlMode: String, CaseIterable, Identifiable {
    case teleoperated
    case autonomous
    case test

    var id: String { rawValue }

    /// The two low bits of the control byte (offset 3).
    var controlBits: UInt8 {
        switch self {
        case .teleoperated: return 0x00
        case .test:         return 0x01
        case .autonomous:   return 0x02
        }
    }

    /// Short label shown in the UI.
    var label: String {
        switch self {
        case .teleoperated: return "TeleOperated"
        case .autonomous:   return "Autonomous"
        case .test:         return "Test"
        }
    }
}

// MARK: - Alliance station

/// Alliance + driver-station position (offset 5 of the outgoing packet).
enum AllianceStation: UInt8, CaseIterable, Identifiable {
    case red1  = 0
    case red2  = 1
    case red3  = 2
    case blue1 = 3
    case blue2 = 4
    case blue3 = 5

    var id: UInt8 { rawValue }
    var isRed: Bool { rawValue < 3 }
    var position: Int { Int(rawValue % 3) + 1 }

    var label: String {
        "\(isRed ? "Red" : "Blue") \(position)"
    }
}

// MARK: - Joystick snapshot

/// One joystick's instantaneous values, in FRC wire units.
///
/// - `axes`    are signed 8-bit: -127..127 (forward/up is negative for sticks).
/// - `buttons` are booleans; button N (0-based) maps to WPILib button N+1.
/// - `povs`    are degrees 0..359 (0 = up, clockwise) or -1 when released.
struct JoystickState: Equatable {
    var axes: [Int8] = []
    var buttons: [Bool] = []
    var povs: [Int16] = []

    static let empty = JoystickState()

    /// Encodes this joystick as a 0x0C tag (length-prefixed) for the outgoing packet.
    func encodedTag() -> [UInt8] {
        var payload: [UInt8] = []
        payload.append(0x0C)                                   // tag id
        payload.append(UInt8(min(axes.count, 255)))            // axis count
        for a in axes { payload.append(UInt8(bitPattern: a)) } // signed axes

        payload.append(UInt8(min(buttons.count, 255)))         // button count
        let maskBytes = (buttons.count + 7) / 8                 // ceil(n/8)
        var mask = [UInt8](repeating: 0, count: maskBytes)
        for (i, pressed) in buttons.enumerated() where pressed {
            mask[i / 8] |= UInt8(1 << (i % 8))                 // LSB = button 0
        }
        payload.append(contentsOf: mask)

        payload.append(UInt8(min(povs.count, 255)))            // pov count
        for p in povs {                                        // int16 big-endian
            let v = UInt16(bitPattern: p)
            payload.append(UInt8(v >> 8))
            payload.append(UInt8(v & 0xFF))
        }

        // Prefix with the tag size (number of bytes that follow the size byte).
        var tag: [UInt8] = [UInt8(payload.count)]
        tag.append(contentsOf: payload)
        return tag
    }
}

// MARK: - Outgoing control state

/// Everything that determines the bytes of one outgoing control packet.
struct ControlSnapshot {
    var mode: ControlMode = .teleoperated
    var enabled: Bool = false
    var eStop: Bool = false
    var fmsAttached: Bool = false
    var requestReboot: Bool = false
    var requestRestartCode: Bool = false
    var alliance: AllianceStation = .red1
}

// MARK: - Outgoing packet builder

enum OutgoingPacket {
    /// Builds the DS -> roboRIO datagram for the given sequence number, control
    /// state and joystick snapshots.
    static func build(sequence: UInt16,
                      control c: ControlSnapshot,
                      joysticks: [JoystickState]) -> Data {
        var b: [UInt8] = []
        b.append(UInt8(sequence >> 8))      // [0] seq high
        b.append(UInt8(sequence & 0xFF))    // [1] seq low
        b.append(0x01)                      // [2] comm version

        var control = c.mode.controlBits    // [3] control byte
        if c.enabled && !c.eStop { control |= 0x04 }
        if c.fmsAttached         { control |= 0x08 }
        if c.eStop               { control |= 0x80 }
        b.append(control)

        var request: UInt8 = 0              // [4] request byte
        if c.requestReboot      { request |= 0x08 }
        if c.requestRestartCode { request |= 0x04 }
        b.append(request)

        b.append(c.alliance.rawValue)       // [5] alliance station

        for js in joysticks {               // [6..] joystick tags
            b.append(contentsOf: js.encodedTag())
        }
        return Data(b)
    }
}

// MARK: - Incoming status packet

/// Parsed roboRIO -> DS status datagram.
struct RobotStatus: Equatable {
    var sequence: UInt16
    var eStop: Bool
    var brownout: Bool
    var codeInitializing: Bool
    var enabled: Bool
    var mode: ControlMode
    var robotCodePresent: Bool
    var isRoboRIO: Bool
    var voltage: Double
    var requestingDateTime: Bool

    /// Parses an incoming datagram, returning nil if it is too short to be valid.
    static func parse(_ data: Data) -> RobotStatus? {
        let b = [UInt8](data)
        guard b.count >= 8 else { return nil }

        let seq = (UInt16(b[0]) << 8) | UInt16(b[1])
        // b[2] = comm version (0x01)
        let status = b[3]
        let trace  = b[4]
        let voltage = Double(b[5]) + Double(b[6]) / 256.0
        let req = b[7]

        let mode: ControlMode
        switch status & 0x03 {
        case 0x01: mode = .test
        case 0x02: mode = .autonomous
        default:   mode = .teleoperated
        }

        return RobotStatus(
            sequence: seq,
            eStop: status & 0x80 != 0,
            brownout: status & 0x10 != 0,
            codeInitializing: status & 0x08 != 0,
            enabled: status & 0x04 != 0,
            mode: mode,
            robotCodePresent: trace & 0x20 != 0,
            isRoboRIO: trace & 0x10 != 0,
            voltage: voltage,
            requestingDateTime: req & 0x01 != 0
        )
    }
}

// MARK: - Robot addressing

enum RobotAddress {
    /// The team-number IP, 10.TE.AM.2 (e.g. team 1234 -> 10.12.34.2).
    /// Returns nil for team numbers that don't fit the 10.x.y.2 scheme.
    static func ip(forTeam team: Int) -> String? {
        guard team > 0, team <= 25599 else { return nil }
        return "10.\(team / 100).\(team % 100).2"
    }

    /// The mDNS hostname the roboRIO advertises, roboRIO-<team>-FRC.local.
    static func mdns(forTeam team: Int) -> String {
        "roboRIO-\(team)-FRC.local"
    }
}
