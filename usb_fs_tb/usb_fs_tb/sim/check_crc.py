#!/usr/bin/env python3
"""check_crc.py - checks the CRC maths of this project against known USB data.
No simulator needed:  python3 check_crc.py
"""
import random
import sys

passed = 0
failed = 0


def check(name, ok):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL:", name)


def to_bits(data):
    # bytes -> bit list, LSB of each byte first (USB order)
    return [(b >> i) & 1 for b in data for i in range(8)]


def to_bytes(bits):
    # bit list (wire order) -> bytes, first bit = bit 0
    out = []
    for i in range(0, len(bits) - 7, 8):
        out.append(sum(bits[i + j] << j for j in range(8)))
    return out


def reverse(v, width):
    return int(format(v, "0%db" % width)[::-1], 2)


# style 1: shift left, same idea as rtl/usb_pkg.sv
def crc_left(bits, width, poly):
    reg = (1 << width) - 1
    mask = reg
    for d in bits:
        fb = ((reg >> (width - 1)) & 1) ^ d
        reg = (reg << 1) & mask
        if fb:
            reg ^= poly
    return reg


# style 2: reflected, shift right, same idea as tb/usb_ref_pkg.sv
def crc_right(bits, width, poly_rev):
    reg = (1 << width) - 1
    for d in bits:
        fb = (reg & 1) ^ d
        reg >>= 1
        if fb:
            reg ^= poly_rev
    return reg


# style 3: plain polynomial division, no shift register at all.
# register after n bits = (M(x) * x^w + ones * x^n) mod G(x)
def crc_div(bits, width, poly_full):
    n = len(bits)
    m = 0
    for b in bits:
        m = (m << 1) | b
    val = (m << width) ^ (((1 << width) - 1) << n)
    for i in range(val.bit_length() - 1, width - 1, -1):
        if (val >> i) & 1:
            val ^= poly_full << (i - width)
    return val


CRC5_POLY, CRC5_FULL, CRC5_REV = 0x05, 0x25, 0x14          # x^5 + x^2 + 1
CRC16_POLY, CRC16_FULL, CRC16_REV = 0x8005, 0x18005, 0xA001  # x^16 + x^15 + x^2 + 1

PID = {"OUT": 0x1, "IN": 0x9, "SOF": 0x5, "SETUP": 0xD,
       "DATA0": 0x3, "DATA1": 0xB, "ACK": 0x2, "NAK": 0xA, "STALL": 0xE}


def pid_byte(p):
    return ((~p & 0xF) << 4) | p


def token_bytes(pid, addr, endp):
    # sync + pid + 11 field bits + crc5 (sent MSB first), packed like a logic analyser shows it
    field = to_bits([addr])[:7] + to_bits([endp])[:4]
    crc = ~crc_left(field, 5, CRC5_POLY) & 0x1F
    wire = to_bits([0x80, pid_byte(pid)]) + field + [(crc >> k) & 1 for k in range(4, -1, -1)]
    return to_bytes(wire)


def data_bytes(pid, payload):
    field = to_bits(payload)
    crc = ~crc_left(field, 16, CRC16_POLY) & 0xFFFF
    wire = to_bits([0x80, pid_byte(pid)]) + field + [(crc >> k) & 1 for k in range(15, -1, -1)]
    return to_bytes(wire)


# ---- 1) PID bytes (PID + its complement) ----
known_pid_bytes = {"OUT": 0xE1, "IN": 0x69, "SOF": 0xA5, "SETUP": 0x2D, "DATA0": 0xC3,
                   "DATA1": 0x4B, "ACK": 0xD2, "NAK": 0x5A, "STALL": 0x1E}
for name, val in known_pid_bytes.items():
    check("PID byte " + name, pid_byte(PID[name]) == val)

# ---- 2) known packets seen in real USB traces ----
check("SETUP addr0 endp0 = 2D 00 10", token_bytes(PID["SETUP"], 0, 0)[1:4] == [0x2D, 0x00, 0x10])
check("OUT   addr0 endp0 = E1 00 10", token_bytes(PID["OUT"], 0, 0)[1:4] == [0xE1, 0x00, 0x10])
check("empty DATA0 = C3 00 00", data_bytes(PID["DATA0"], [])[1:4] == [0xC3, 0x00, 0x00])
get_desc = [0x80, 0x06, 0x00, 0x01, 0x00, 0x00, 0x40, 0x00]
check("GET_DESCRIPTOR DATA0 = C3 80 06 00 01 00 00 40 00 DD 94",
      data_bytes(PID["DATA0"], get_desc)[1:] == [0xC3] + get_desc + [0xDD, 0x94])

dev_desc = [0x12, 0x01, 0x10, 0x01, 0x00, 0x00, 0x00, 0x08]
check("DATA1 12 01 10 01 00 00 00 08 + CRC 11 77",
      data_bytes(PID["DATA1"], dev_desc)[1:] == [0x4B] + dev_desc + [0x11, 0x77])
check("IN addr0 endp0 = 69 00 10", token_bytes(PID["IN"], 0, 0)[1:4] == [0x69, 0x00, 0x10])

# ---- 3) CRC residual: run the CRC over data + CRC and you always get the same constant ----
# USB 2.0 spec: CRC5 residual 01100b, CRC16 residual 1000000000001101b
for _ in range(200):
    field = [random.getrandbits(1) for _ in range(11)]
    c = ~crc_left(field, 5, CRC5_POLY) & 0x1F
    tail = [(c >> k) & 1 for k in range(4, -1, -1)]
    check("CRC5 residual", crc_left(field + tail, 5, CRC5_POLY) == 0b01100)
for _ in range(200):
    n = random.randint(0, 64)
    field = to_bits([random.getrandbits(8) for _ in range(n)])
    c = ~crc_left(field, 16, CRC16_POLY) & 0xFFFF
    tail = [(c >> k) & 1 for k in range(15, -1, -1)]
    check("CRC16 residual", crc_left(field + tail, 16, CRC16_POLY) == 0x800D)

# ---- 4) the three CRC styles must agree (shift left / reflected / polynomial division) ----
for _ in range(500):
    f5 = [random.getrandbits(1) for _ in range(11)]
    a = crc_left(f5, 5, CRC5_POLY)
    check("CRC5 left vs reflected", reverse(a, 5) == crc_right(f5, 5, CRC5_REV))
    check("CRC5 left vs division", a == crc_div(f5, 5, CRC5_FULL))
    n = random.randint(0, 64)
    f16 = to_bits([random.getrandbits(8) for _ in range(n)])
    b = crc_left(f16, 16, CRC16_POLY)
    check("CRC16 left vs reflected", reverse(b, 16) == crc_right(f16, 16, CRC16_REV))
    check("CRC16 left vs division", b == crc_div(f16, 16, CRC16_FULL))

print("check_crc: passed=%d failed=%d" % (passed, failed))
sys.exit(1 if failed else 0)
