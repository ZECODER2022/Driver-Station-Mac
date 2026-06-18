//
//  ConsoleView.swift
//  Best-effort roboRIO console output (NetConsole / UDP 6666).
//

import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject private var ds: DriverStation

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Robot Console").font(.headline)
                Spacer()
                Button("Clear") { ds.console.clear() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(ds.console.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                        if ds.console.lines.isEmpty {
                            Text("Waiting for robot console output on UDP 6666…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.04)))
                .onChange(of: ds.console.lines.count) { count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
        }
    }
}
