# FRC Driver Station for macOS

An unofficial, native macOS Driver Station for FIRST Robotics Competition robots.
It speaks the roboRIO communication protocol directly (UDP 1110/1150), reads game
controllers through Apple's GameController framework, and presents a SwiftUI
control panel.

> ⚠️ **Unofficial / community software.** Not affiliated with *FIRST* or National
> Instruments. The official Driver Station (Windows-only) is required for official
> FRC events. Use this for development, testing, and off-season work.

---

## Features

- **Full control link** to the roboRIO at 50 Hz: Enable / Disable, TeleOperated /
  Autonomous / Test modes, and a latching **E‑Stop**.
- **Live robot status**: communications, robot-code, battery voltage, brownout,
  and e‑stop, decoded from the roboRIO's status packets.
- **Game controllers** mapped to WPILib's standard Xbox layout (6 axes, 10
  buttons, D‑pad → POV), with a live USB Devices view.
- **Team-number addressing** (`10.TE.AM.2`) with an address override field for
  mDNS (`roboRIO-####-FRC.local`), USB (`172.22.11.2`) or simulation
  (`127.0.0.1`).
- **Robot console** viewer (best-effort NetConsole on UDP 6666).
- **Reboot roboRIO** / **Restart robot code** requests.
- Keyboard: **Space = E‑Stop**, **Enter = Disable** (matching the official DS).

## Install (for users)

1. Download **`FRC-Driver-Station-x.y.z.dmg`** from the
   [Releases page](../../releases).
2. Open the DMG and drag **FRC Driver Station** into **Applications**.
3. **First launch only** — because this app isn't signed with a paid Apple
   Developer certificate, macOS Gatekeeper will warn you. Do one of:
   - **Right-click** the app → **Open** → **Open** in the dialog, **or**
   - run this in Terminal once:
     ```sh
     xattr -dr com.apple.quarantine "/Applications/FRC Driver Station.app"
     ```

After that it opens normally. (Prefer not to trust a binary? Build it yourself
from source — see below.)

## Requirements (to build from source)

- macOS 26 (Tahoe) or newer, Apple Silicon.
- Swift toolchain (the Xcode Command Line Tools provide `swiftc`). Full Xcode is
  **not** required.

## Build & run

```sh
./build.sh        # compile into "build/FRC Driver Station.app"
./build.sh run    # compile, then launch
./build.sh test   # run the headless wire-protocol self-test
```

> This project compiles directly with `swiftc` rather than Swift Package Manager,
> because SwiftPM is currently broken on this macOS 27 / Swift 6.4 Command-Line-
> Tools install (`swift-package` fails to load `BuildServerProtocol.framework`).
> `build.sh` assembles a proper `.app` bundle from the compiled binary.

To install, drag `build/FRC Driver Station.app` to `/Applications`.

## Usage

1. Enter your **team number** (e.g. `1234` → `10.12.34.2`) and click **Apply**.
   For simulation, put `127.0.0.1` in the address-override field.
2. Wait for **Communications** and **Robot Code** to turn green.
3. Pick a mode and press **Enable**. Press **Disable** (or Enter) to stop;
   **E‑STOP** (or Space) for an emergency stop.

## How it works

| Direction | Port | Rate | Payload |
|-----------|------|------|---------|
| DS → roboRIO | UDP 1110 | every 20 ms | seq, control byte, request byte, alliance, joystick tags |
| roboRIO → DS | UDP 1150 | in reply | seq, status byte, trace byte, battery voltage, tags |

The protocol bytes are documented inline in
[`Sources/Protocol/Protocol.swift`](Sources/Protocol/Protocol.swift) and pinned
by assertions in [`Sources/Protocol/SelfTest.swift`](Sources/Protocol/SelfTest.swift)
(`./build.sh test`). The implementation follows the reverse-engineered FRC
protocol documented at <https://frcture.readthedocs.io/>.

### Project layout

```
Sources/
  Protocol/   ControlMode, AllianceStation, packet encode/decode, self-test
  Net/        UDPLink (50 Hz send + 1150 receive), ConsoleListener (6666)
  Input/      JoystickManager (GameController → FRC mapping)
  Core/       DriverStation (state, safety rules, glue)
  UI/         SwiftUI views (control panel, USB devices, console)
  App/        entry point + App scene
tools/
  fake_robot.py   simulated roboRIO for end-to-end testing
```

### End-to-end test against a simulated roboRIO

```sh
python3 tools/fake_robot.py 3 &                 # pretends to be the robot on :1110
FRC_DS_ADDRESS=127.0.0.1 FRC_DS_DEBUG=1 \
  "build/FRC Driver Station.app/Contents/MacOS/FRCDriverStation"
```

The robot script verifies the DS sends a well-formed ~50 Hz stream; `FRC_DS_DEBUG=1`
logs each parsed reply to stderr.

## Limitations / not yet implemented

- No TCP channel (port 1740): joystick **names/descriptors**, game-specific data,
  and DS-side error/event logging are not sent. Joystick axis/button **values**
  (which is what robot code reads) *are* sent over UDP and work normally.
- No FMS connection (port 1115) — direct-to-robot only.
- No date/time or timezone tags (the robot requests these to set its clock).
- Practice-mode timing and the dashboard launcher are out of scope.
- The console viewer is best-effort and may show framing artifacts.

## License

Provided as-is for the FRC community.
