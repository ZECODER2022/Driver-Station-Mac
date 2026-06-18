//
//  SelfTest.swift
//  Headless verification of the wire protocol. Run with `--selftest`.
//
//  These assert the exact bytes the protocol layer must produce/consume so a
//  regression here fails loudly instead of silently sending a malformed packet
//  to a real robot.
//

import Foundation

private var failures = 0

private func expect(_ name: String, _ actual: [UInt8], _ expected: [UInt8]) {
    if actual == expected {
        print("  ok   \(name)")
    } else {
        failures += 1
        print("  FAIL \(name)")
        print("       expected: \(hex(expected))")
        print("       actual:   \(hex(actual))")
    }
}

private func expect(_ name: String, _ cond: Bool) {
    if cond { print("  ok   \(name)") }
    else { failures += 1; print("  FAIL \(name)") }
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

/// Runs all protocol self-tests; returns true if everything passed.
func runSelfTest() -> Bool {
    failures = 0
    print("FRC Driver Station protocol self-test")

    // 1. Disabled teleop, Red 1, no joysticks.
    expect("disabled teleop / red1",
           [UInt8](OutgoingPacket.build(
                sequence: 1,
                control: ControlSnapshot(mode: .teleoperated, enabled: false, alliance: .red1),
                joysticks: [])),
           [0x00, 0x01, 0x01, 0x00, 0x00, 0x00])

    // 2. Enabled autonomous, Blue 2.
    expect("enabled auto / blue2",
           [UInt8](OutgoingPacket.build(
                sequence: 2,
                control: ControlSnapshot(mode: .autonomous, enabled: true, alliance: .blue2),
                joysticks: [])),
           [0x00, 0x02, 0x01, 0x06, 0x00, 0x04])

    // 3. E-stop forces enabled off and sets bit 0x80.
    expect("estop clears enabled",
           [UInt8](OutgoingPacket.build(
                sequence: 3,
                control: ControlSnapshot(mode: .teleoperated, enabled: true, eStop: true, alliance: .red1),
                joysticks: [])),
           [0x00, 0x03, 0x01, 0x80, 0x00, 0x00])

    // 4. Request bits: reboot (0x08) + restart-code (0x04) = 0x0C.
    expect("reboot + restart request",
           [UInt8](OutgoingPacket.build(
                sequence: 4,
                control: ControlSnapshot(requestReboot: true, requestRestartCode: true, alliance: .red1),
                joysticks: [])),
           [0x00, 0x04, 0x01, 0x00, 0x0C, 0x00])

    // 5. Joystick tag: 2 axes [127, -128], 3 buttons [t,f,t], 1 POV [90].
    //    payload = 0C 02 7F 80 03 05 01 00 5A  (size 0x09)
    let js = JoystickState(axes: [127, -128], buttons: [true, false, true], povs: [90])
    expect("joystick tag encoding",
           js.encodedTag(),
           [0x09, 0x0C, 0x02, 0x7F, 0x80, 0x03, 0x05, 0x01, 0x00, 0x5A])

    // 6. Empty joystick tag: size 4 -> 0x0C 00 00 00.
    expect("empty joystick tag",
           JoystickState.empty.encodedTag(),
           [0x04, 0x0C, 0x00, 0x00, 0x00])

    // 7. POV released encodes as -1 -> 0xFF 0xFF (payload 6 bytes, size 0x06).
    expect("pov released",
           JoystickState(povs: [-1]).encodedTag(),
           [0x06, 0x0C, 0x00, 0x00, 0x01, 0xFF, 0xFF])

    // 8. Incoming status parse: enabled teleop, code present, 12.5 V.
    let status = RobotStatus.parse(Data([0x00, 0x05, 0x01, 0x04, 0x20, 0x0C, 0x80, 0x00]))
    expect("status parses", status != nil)
    if let s = status {
        expect("status: enabled",  s.enabled)
        expect("status: teleop",   s.mode == .teleoperated)
        expect("status: code",     s.robotCodePresent)
        expect("status: voltage",  abs(s.voltage - 12.5) < 0.0001)
        expect("status: no estop", s.eStop == false)
    }

    // 9. Brownout + e-stop + autonomous, code initializing.
    let s2 = RobotStatus.parse(Data([0x12, 0x34, 0x01, 0x80 | 0x10 | 0x08 | 0x02, 0x00, 0x07, 0x40, 0x01]))
    expect("status2 parses", s2 != nil)
    if let s = s2 {
        expect("status2: estop",     s.eStop)
        expect("status2: brownout",  s.brownout)
        expect("status2: code init", s.codeInitializing)
        expect("status2: auto",      s.mode == .autonomous)
        expect("status2: req date",  s.requestingDateTime)
        expect("status2: voltage",   abs(s.voltage - (7.0 + 64.0 / 256.0)) < 0.0001)
    }

    // 10. Team-number -> IP mapping.
    expect("ip team 1234",  RobotAddress.ip(forTeam: 1234) == "10.12.34.2")
    expect("ip team 9",     RobotAddress.ip(forTeam: 9) == "10.0.9.2")
    expect("ip team 100",   RobotAddress.ip(forTeam: 100) == "10.1.0.2")
    expect("ip team 0 nil", RobotAddress.ip(forTeam: 0) == nil)
    expect("mdns 1234",     RobotAddress.mdns(forTeam: 1234) == "roboRIO-1234-FRC.local")

    print(failures == 0 ? "\nAll tests passed." : "\n\(failures) test(s) FAILED.")
    return failures == 0
}
