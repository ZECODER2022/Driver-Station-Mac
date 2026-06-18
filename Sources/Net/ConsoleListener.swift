//
//  ConsoleListener.swift
//  Best-effort roboRIO console (NetConsole) viewer.
//
//  The roboRIO broadcasts console/print output as UDP datagrams on port 6666.
//  We bind that port and surface any printable text. This is intentionally
//  lightweight and tolerant of framing bytes from the riolog protocol.
//

import Foundation
import Darwin

final class ConsoleListener: ObservableObject {
    @Published private(set) var lines: [String] = []

    private let port: UInt16 = 6666
    private let maxLines = 600
    private var fd: Int32 = -1
    private var thread: Thread?
    private var running = false

    func start() {
        guard !running else { return }
        running = true
        openSocket()
        let t = Thread { [weak self] in self?.loop() }
        t.name = "frcds.console"
        thread = t
        t.start()
    }

    func stop() {
        running = false
        if fd >= 0 { close(fd); fd = -1 }
    }

    func clear() { lines = [] }

    private func openSocket() {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    private func loop() {
        var buf = [UInt8](repeating: 0, count: 4096)
        while running {
            guard fd >= 0 else { break }
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { continue }
            // Keep printable ASCII, tabs and newlines; drop framing/control bytes.
            let bytes = buf[0..<n].filter { $0 == 0x09 || $0 == 0x0A || ($0 >= 0x20 && $0 < 0x7F) }
            guard let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty else { continue }
            let newLines = text
                .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !newLines.isEmpty else { continue }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lines.append(contentsOf: newLines)
                if self.lines.count > self.maxLines {
                    self.lines.removeFirst(self.lines.count - self.maxLines)
                }
            }
        }
    }
}
