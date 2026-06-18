//
//  UDPLink.swift
//  Low-level UDP transport to the roboRIO.
//
//  Uses a single BSD socket bound to local UDP port 1150 (where the roboRIO
//  sends its status) and sends control packets from that same socket to the
//  robot on port 1110. A 20 ms dispatch timer drives the 50 Hz control stream;
//  a background thread drains incoming status packets.
//
//  Plain Darwin sockets are used deliberately: they give exact control over the
//  source/destination ports the FRC protocol requires and behave predictably.
//

import Foundation
import Darwin

final class UDPLink {

    // Ports defined by the FRC protocol.
    private let robotPort: UInt16 = 1110   // we send here
    private let dsPort: UInt16    = 1150   // we listen here

    // MARK: Callbacks (invoked on a background queue)

    /// Supplies the current joystick snapshots at send time.
    var joystickProvider: (() -> [JoystickState])?
    /// Delivers a parsed status packet from the robot.
    var onStatus: ((RobotStatus) -> Void)?

    // MARK: Shared state (guarded by `lock`)

    private let lock = NSLock()
    private var control = ControlSnapshot()
    private var target: sockaddr_in?
    private var sequence: UInt16 = 0
    private var rebootUntil = Date.distantPast
    private var restartUntil = Date.distantPast
    private var _lastReceive = Date.distantPast
    private var _sentCount: UInt64 = 0
    private var _receivedCount: UInt64 = 0

    // MARK: Runtime

    private var fd: Int32 = -1
    private let sendQueue = DispatchQueue(label: "frcds.udp.send")
    private let resolveQueue = DispatchQueue(label: "frcds.udp.resolve")
    private var timer: DispatchSourceTimer?
    private var recvThread: Thread?
    private var running = false

    // MARK: Lifecycle

    func start() {
        guard !running else { return }
        running = true
        openSocket()
        startReceiveLoop()
        startSendTimer()
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    // MARK: Public state accessors

    func setControl(_ c: ControlSnapshot) {
        lock.lock(); control = c; lock.unlock()
    }

    /// Sets the destination host (an IP or resolvable hostname). Resolution is
    /// done off the send path so a slow DNS/mDNS lookup never stalls the 50 Hz loop.
    func setHost(_ host: String?) {
        guard let host = host, !host.isEmpty else {
            lock.lock(); target = nil; lock.unlock()
            return
        }
        resolveQueue.async { [weak self] in
            guard let self = self else { return }
            let resolved = self.resolve(host)
            self.lock.lock(); self.target = resolved; self.lock.unlock()
        }
    }

    func pulseReboot()      { lock.lock(); rebootUntil  = Date().addingTimeInterval(1.0); lock.unlock() }
    func pulseRestartCode() { lock.lock(); restartUntil = Date().addingTimeInterval(1.0); lock.unlock() }

    var lastReceive: Date  { lock.lock(); defer { lock.unlock() }; return _lastReceive }
    var sentCount: UInt64  { lock.lock(); defer { lock.unlock() }; return _sentCount }
    var receivedCount: UInt64 { lock.lock(); defer { lock.unlock() }; return _receivedCount }

    // MARK: Socket setup

    private func openSocket() {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { perror("socket"); return }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        // Wake the recv loop a few times a second so it can observe `running`.
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = dsPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult != 0 { perror("bind(1150)") }
    }

    // MARK: Send path (50 Hz)

    private func startSendTimer() {
        let t = DispatchSource.makeTimerSource(queue: sendQueue)
        t.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.sendOnce() }
        timer = t
        t.resume()
    }

    private func sendOnce() {
        guard fd >= 0 else { return }

        lock.lock()
        guard var addr = target else { lock.unlock(); return }
        sequence = sequence &+ 1
        let seq = sequence
        var c = control
        let now = Date()
        c.requestReboot = now < rebootUntil
        c.requestRestartCode = now < restartUntil
        lock.unlock()

        let joysticks = joystickProvider?() ?? []
        let packet = OutgoingPacket.build(sequence: seq, control: c, joysticks: joysticks)

        let sent = packet.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, raw.baseAddress, raw.count, 0, sa,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent > 0 {
            lock.lock(); _sentCount &+= 1; lock.unlock()
        }
    }

    // MARK: Receive path

    private func startReceiveLoop() {
        let thread = Thread { [weak self] in self?.receiveLoop() }
        thread.name = "frcds.udp.recv"
        thread.stackSize = 256 * 1024
        recvThread = thread
        thread.start()
    }

    private func receiveLoop() {
        var buf = [UInt8](repeating: 0, count: 2048)
        while running {
            guard fd >= 0 else { break }
            var from = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, 0, sa, &fromLen)
                }
            }
            if n > 0 {
                let data = Data(buf[0..<n])
                if let status = RobotStatus.parse(data) {
                    lock.lock(); _lastReceive = Date(); _receivedCount &+= 1; lock.unlock()
                    onStatus?(status)
                }
            }
            // n <= 0 is typically the recv timeout firing; loop and re-check `running`.
        }
    }

    // MARK: Hostname resolution

    private func resolve(_ host: String) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP

        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(robotPort), &hints, &res)
        guard rc == 0, let info = res else { return nil }
        defer { freeaddrinfo(res) }

        guard let sa = info.pointee.ai_addr else { return nil }
        return sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }
}
