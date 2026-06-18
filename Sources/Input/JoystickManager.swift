//
//  JoystickManager.swift
//  Reads connected game controllers via Apple's GameController framework and
//  maps them to FRC joystick wire values using WPILib's standard layout.
//
//  Axis order (matches WPILib XboxController):
//      0 LeftX  1 LeftY  2 LeftTrigger  3 RightTrigger  4 RightX  5 RightY
//  Button order (WPILib button N = index N-1):
//      A B X Y LeftBumper RightBumper Back Start LeftStick RightStick
//  POV: D-pad as a single hat (0 = up, clockwise; -1 = released).
//

import Foundation
import GameController

final class JoystickManager: ObservableObject {

    /// Snapshot used by the UI to render live joystick activity.
    struct Info: Identifiable {
        let id: Int
        let name: String
        let state: JoystickState
    }

    @Published private(set) var infos: [Info] = []

    private let lock = NSLock()
    private var controllers: [GCController] = []
    private var states: [JoystickState] = []
    private var names: [String] = []

    init() {
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(controllersChanged),
                       name: .GCControllerDidConnect, object: nil)
        nc.addObserver(self, selector: #selector(controllersChanged),
                       name: .GCControllerDidDisconnect, object: nil)
        controllersChanged()
    }

    /// Current joystick snapshots, in stable port order, for the send loop.
    /// Thread-safe.
    func currentStates() -> [JoystickState] {
        lock.lock(); defer { lock.unlock() }
        return states
    }

    /// Republish the latest values to the UI (called ~10 Hz from the main loop).
    func refreshUI() { publish() }

    @objc private func controllersChanged() {
        let list = GCController.controllers()
        lock.lock()
        controllers = list
        states = list.map { Self.read($0) }
        names = list.enumerated().map { index, c in
            c.vendorName ?? "Controller \(index)"
        }
        lock.unlock()
        for c in list { attach(c) }
        publish()
    }

    private func attach(_ controller: GCController) {
        controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let self = self, let controller = controller else { return }
            self.lock.lock()
            if let idx = self.controllers.firstIndex(where: { $0 === controller }) {
                self.states[idx] = Self.read(controller)
            }
            self.lock.unlock()
        }
    }

    private func publish() {
        lock.lock()
        let snapshot = zip(names, states).enumerated().map { index, pair in
            Info(id: index, name: pair.0, state: pair.1)
        }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.infos = snapshot }
    }

    // MARK: - Controller -> FRC mapping

    private static func read(_ controller: GCController) -> JoystickState {
        guard let g = controller.extendedGamepad else {
            return .empty
        }

        let axes: [Int8] = [
            i8(g.leftThumbstick.xAxis.value),
            i8(-g.leftThumbstick.yAxis.value),   // FRC: stick forward/up is negative
            i8(g.leftTrigger.value),
            i8(g.rightTrigger.value),
            i8(g.rightThumbstick.xAxis.value),
            i8(-g.rightThumbstick.yAxis.value),
        ]

        let buttons: [Bool] = [
            g.buttonA.isPressed,
            g.buttonB.isPressed,
            g.buttonX.isPressed,
            g.buttonY.isPressed,
            g.leftShoulder.isPressed,
            g.rightShoulder.isPressed,
            g.buttonOptions?.isPressed ?? false,    // "Back" / "View"
            g.buttonMenu.isPressed,                  // "Start" / "Menu"
            g.leftThumbstickButton?.isPressed ?? false,
            g.rightThumbstickButton?.isPressed ?? false,
        ]

        return JoystickState(axes: axes, buttons: buttons, povs: [pov(g.dpad)])
    }

    private static func i8(_ value: Float) -> Int8 {
        let clamped = max(-1, min(1, value))
        return Int8(max(-127, min(127, (clamped * 127).rounded())))
    }

    private static func pov(_ d: GCControllerDirectionPad) -> Int16 {
        let up = d.up.isPressed, down = d.down.isPressed
        let left = d.left.isPressed, right = d.right.isPressed
        switch (up, right, down, left) {
        case (true,  false, false, false): return 0
        case (true,  true,  false, false): return 45
        case (false, true,  false, false): return 90
        case (false, true,  true,  false): return 135
        case (false, false, true,  false): return 180
        case (false, false, true,  true):  return 225
        case (false, false, false, true):  return 270
        case (true,  false, false, true):  return 315
        default:                           return -1
        }
    }
}
