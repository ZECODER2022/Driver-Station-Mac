#!/usr/bin/env python3
"""
Simulated roboRIO for end-to-end testing of the Driver Station.

Binds UDP 1110 (where the DS sends control packets), validates each incoming
packet against the FRC protocol, and replies on the sender's port (1150) with a
status packet reporting robot code present and 12.34 V. Prints a summary after
`--seconds` and exits non-zero if the DS stream looked malformed.
"""
import socket
import struct
import sys
import time

DURATION = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", 1110))
sock.settimeout(0.25)

received = 0
bad = 0
last_seq = None
seq_ok = True
first_control = None

start = time.time()
while time.time() - start < DURATION:
    try:
        data, addr = sock.recvfrom(2048)
    except socket.timeout:
        continue

    received += 1
    # Validate the fixed header: >=6 bytes, comm version 0x01.
    if len(data) < 6 or data[2] != 0x01:
        bad += 1
        continue

    seq = (data[0] << 8) | data[1]
    control = data[3]
    if first_control is None:
        first_control = control
    if last_seq is not None and seq != ((last_seq + 1) & 0xFFFF):
        seq_ok = False
    last_seq = seq

    # Reply: status byte mirrors enabled/mode, trace bit5 = robot code present,
    # battery 12.34 V (0x0C + 0x57/256 ~= 12.34).
    status = control & 0x07            # enabled + mode bits
    trace = 0x20 | 0x10                # robot code + is-roboRIO
    reply = struct.pack(
        ">HBBBBBB",
        seq, 0x01, status, trace, 0x0C, 0x57, 0x00
    )
    sock.sendto(reply, addr)

elapsed = time.time() - start
rate = received / elapsed if elapsed else 0
print(f"packets_received={received}")
print(f"rate_hz={rate:.1f}")
print(f"malformed={bad}")
print(f"sequence_monotonic={seq_ok}")
print(f"first_control_byte=0x{(first_control or 0):02X}")

ok = received > 0 and bad == 0 and seq_ok and 30 <= rate <= 70
print("RESULT=" + ("PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)
