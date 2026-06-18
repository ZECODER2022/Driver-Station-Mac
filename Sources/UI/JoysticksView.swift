//
//  JoysticksView.swift
//  Live view of connected USB/Bluetooth game controllers and their FRC values.
//

import SwiftUI

struct JoysticksView: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        Group {
            if ds.joysticks.infos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No controllers detected")
                        .foregroundColor(.secondary)
                    Text("Connect an Xbox/PlayStation/MFi controller. Port = list order.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(ds.joysticks.infos) { info in
                            JoystickCard(port: info.id, name: info.name, state: info.state)
                        }
                    }
                    .padding(4)
                }
            }
        }
    }
}

private struct JoystickCard: View {
    let port: Int
    let name: String
    let state: JoystickState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Port \(port)").font(.headline)
                Text(name).foregroundColor(.secondary)
                Spacer()
            }

            // Axes
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(state.axes.enumerated()), id: \.offset) { idx, value in
                    HStack(spacing: 8) {
                        Text(axisName(idx)).frame(width: 92, alignment: .leading)
                            .font(.caption)
                        AxisBar(value: Double(value) / 127.0)
                        Text(String(format: "%+.2f", Double(value) / 127.0))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }

            // Buttons
            HStack(spacing: 6) {
                ForEach(Array(state.buttons.enumerated()), id: \.offset) { idx, pressed in
                    Text("\(idx + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(pressed ? Color.accentColor : Color.gray.opacity(0.25))
                        )
                        .foregroundColor(pressed ? .white : .secondary)
                }
            }

            if let pov = state.povs.first {
                Text("POV: \(pov < 0 ? "—" : "\(pov)°")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.2)))
    }

    private func axisName(_ i: Int) -> String {
        switch i {
        case 0: return "0 LeftX"
        case 1: return "1 LeftY"
        case 2: return "2 L-Trig"
        case 3: return "3 R-Trig"
        case 4: return "4 RightX"
        case 5: return "5 RightY"
        default: return "\(i)"
        }
    }
}

private struct AxisBar: View {
    let value: Double   // -1 ... 1
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let mid = w / 2
            let clamped = max(-1, min(1, value))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2))
                Rectangle().fill(Color.secondary.opacity(0.4))
                    .frame(width: 1)
                    .position(x: mid, y: geo.size.height / 2)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: abs(clamped) * mid)
                    .offset(x: clamped >= 0 ? mid : mid - abs(clamped) * mid)
            }
        }
        .frame(height: 12)
    }
}
