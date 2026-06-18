//
//  ContentView.swift
//  Main Driver Station window.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            ControlBar()
            Divider()
            ConnectionBar()
            Divider()
            TabView {
                OperationTab().tabItem { Text("Operation") }
                JoysticksView().tabItem { Text("USB Devices") }
                ConsoleView().tabItem { Text("Console") }
            }
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Header (status lamps + battery)

private struct HeaderView: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                StatusLamp(label: "Communications", on: ds.robotComms)
                StatusLamp(label: "Robot Code", on: ds.robotCode)
                StatusLamp(label: "Joysticks", on: !ds.joysticks.infos.isEmpty)
            }
            .frame(width: 200, alignment: .leading)

            Divider().frame(height: 64)

            VStack(spacing: 2) {
                Text(stateText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(stateColor)
                Text(ds.mode.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 64)

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f V", ds.voltage))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(batteryColor)
                    .monospacedDigit()
                Text(ds.brownout ? "BROWNOUT" : "Battery")
                    .font(.caption)
                    .foregroundColor(ds.brownout ? .orange : .secondary)
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(16)
    }

    private var stateText: String {
        if ds.isEStopped { return "EMERGENCY STOPPED" }
        if !ds.robotComms { return "No Robot Communication" }
        if !ds.robotCode { return "No Robot Code" }
        return ds.enabled ? "ENABLED" : "Disabled"
    }

    private var stateColor: Color {
        if ds.isEStopped { return .red }
        if !ds.robotComms || !ds.robotCode { return .secondary }
        return ds.enabled ? .green : .primary
    }

    private var batteryColor: Color {
        if ds.brownout { return .orange }
        if !ds.robotComms { return .secondary }
        switch ds.voltage {
        case 12...:   return .green
        case 10..<12: return .yellow
        default:      return .red
        }
    }
}

// MARK: - Control bar (mode + enable/disable/estop)

private struct ControlBar: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        HStack(spacing: 16) {
            Picker("", selection: Binding(get: { ds.mode }, set: { ds.mode = $0 })) {
                ForEach(ControlMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(width: 150)
            .disabled(ds.enabled)

            Spacer()

            Button(action: { ds.enable() }) {
                Text("Enable")
                    .frame(width: 110, height: 52)
            }
            .buttonStyle(BigButtonStyle(tint: .green, active: ds.enabled))
            .disabled(!ds.canEnable)

            Button(action: { ds.disable() }) {
                Text("Disable")
                    .frame(width: 110, height: 52)
            }
            .buttonStyle(BigButtonStyle(tint: .gray, active: !ds.enabled && !ds.isEStopped))
            .keyboardShortcut(.return, modifiers: [])

            Button(action: { ds.isEStopped ? ds.clearEStop() : ds.emergencyStop() }) {
                Text(ds.isEStopped ? "Clear\nE-Stop" : "E-STOP")
                    .multilineTextAlignment(.center)
                    .frame(width: 110, height: 52)
            }
            .buttonStyle(BigButtonStyle(tint: .red, active: ds.isEStopped))
            .keyboardShortcut(.space, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Connection bar

private struct ConnectionBar: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        HStack(spacing: 14) {
            LabeledField(label: "Team #") {
                TextField("0", text: $ds.teamNumberText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { ds.applyConnectionSettings() }
            }

            LabeledField(label: "Address override") {
                TextField("auto (10.TE.AM.2)", text: $ds.addressOverride)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .onSubmit { ds.applyConnectionSettings() }
            }

            Button("Apply") { ds.applyConnectionSettings() }

            LabeledField(label: "Alliance") {
                Picker("", selection: Binding(get: { ds.alliance }, set: { ds.alliance = $0 })) {
                    ForEach(AllianceStation.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 90)
            }

            Spacer()

            Text("→ \(ds.resolvedAddress)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Operation tab (diagnostics)

private struct OperationTab: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Status")
                InfoRow("Robot state", ds.enabled ? "Enabled" : "Disabled")
                InfoRow("Mode", ds.mode.label)
                InfoRow("Communications", ds.robotComms ? "Connected" : "—")
                InfoRow("Robot code", ds.robotCode ? "Running" :
                            (ds.lastStatus?.codeInitializing == true ? "Initializing" : "—"))
                InfoRow("Battery", String(format: "%.2f V", ds.voltage))
                InfoRow("Brownout", ds.brownout ? "YES" : "No")
                InfoRow("E-Stop", ds.isEStopped ? "ENGAGED" : "No")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Connection")
                InfoRow("Resolved address", ds.resolvedAddress)
                InfoRow("Packets sent", "\(ds.packetsSent)")
                InfoRow("Packets received", "\(ds.packetsReceived)")
                InfoRow("Joysticks", "\(ds.joysticks.infos.count)")

                Spacer().frame(height: 8)
                SectionTitle("Robot actions")
                HStack {
                    Button("Restart Robot Code") { ds.restartRobotCode() }
                    Button("Reboot roboRIO") { ds.rebootRoboRIO() }
                }
                .disabled(!ds.robotComms)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }
}

// MARK: - Reusable pieces

struct StatusLamp: View {
    let label: String
    let on: Bool
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(on ? Color.green : Color.red.opacity(0.75))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1))
            Text(label).font(.system(size: 13))
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content
        }
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).padding(.bottom, 2)
    }
}

private struct InfoRow: View {
    let key: String, value: String
    init(_ key: String, _ value: String) { self.key = key; self.value = value }
    var body: some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .frame(width: 260)
    }
}

struct BigButtonStyle: ButtonStyle {
    let tint: Color
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? tint : tint.opacity(0.45))
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.black.opacity(0.2), lineWidth: 1)
            )
    }
}
