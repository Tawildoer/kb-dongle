// KBReceiver — receives HID frames from KB Dongle over USB serial and injects them
// as keyboard/mouse events on this Mac.
//
// Build: swiftc KBReceiver.swift -o KBReceiver -framework CoreGraphics -framework AppKit
// Run:   ./KBReceiver
// Requires: Accessibility permission (System Settings → Privacy → Accessibility → add Terminal or this binary)

import Foundation
import CoreGraphics
import AppKit

// MARK: - HID → CGKeyCode mapping (USB HID Usage Page 0x07)

let hidToCGKey: [UInt8: CGKeyCode] = [
    0x04: 0x00, 0x05: 0x0B, 0x06: 0x08, 0x07: 0x02, 0x08: 0x0E, 0x09: 0x03,
    0x0A: 0x05, 0x0B: 0x04, 0x0C: 0x22, 0x0D: 0x26, 0x0E: 0x28, 0x0F: 0x25,
    0x10: 0x2E, 0x11: 0x2D, 0x12: 0x1F, 0x13: 0x23, 0x14: 0x0C, 0x15: 0x0F,
    0x16: 0x01, 0x17: 0x11, 0x18: 0x20, 0x19: 0x09, 0x1A: 0x0D, 0x1B: 0x07,
    0x1C: 0x10, 0x1D: 0x06,                                         // y, z
    0x1E: 0x12, 0x1F: 0x13, 0x20: 0x14, 0x21: 0x15, 0x22: 0x17,   // 1-5
    0x23: 0x16, 0x24: 0x1A, 0x25: 0x1C, 0x26: 0x19, 0x27: 0x1D,   // 6-0
    0x28: 0x24, // Return
    0x29: 0x35, // Escape
    0x2A: 0x33, // Backspace
    0x2B: 0x30, // Tab
    0x2C: 0x31, // Space
    0x2D: 0x1B, // -
    0x2E: 0x18, // =
    0x2F: 0x21, // [
    0x30: 0x1E, // ]
    0x31: 0x2A, // backslash
    0x33: 0x29, // ;
    0x34: 0x27, // '
    0x35: 0x32, // `
    0x36: 0x2B, // ,
    0x37: 0x2F, // .
    0x38: 0x2C, // /
    0x39: 0x39, // Caps Lock
    0x3A: 0x7A, 0x3B: 0x78, 0x3C: 0x63, 0x3D: 0x76, // F1-F4
    0x3E: 0x60, 0x3F: 0x61, 0x40: 0x62, 0x41: 0x64, // F5-F8
    0x42: 0x65, 0x43: 0x6D, 0x44: 0x67, 0x45: 0x6F, // F9-F12
    0x49: 0x72, // Insert
    0x4A: 0x73, // Home
    0x4B: 0x74, // Page Up
    0x4C: 0x75, // Delete (forward)
    0x4D: 0x77, // End
    0x4E: 0x79, // Page Down
    0x4F: 0x7C, // Right arrow
    0x50: 0x7B, // Left arrow
    0x51: 0x7D, // Down arrow
    0x52: 0x7E, // Up arrow
    0x53: 0x47, // Num Lock / Clear
    0x54: 0x4B, 0x55: 0x43, 0x56: 0x4E, 0x57: 0x45, // KP / * - +
    0x58: 0x4C, // KP Enter
    0x59: 0x53, 0x5A: 0x54, 0x5B: 0x55, 0x5C: 0x56, // KP 1-4
    0x5D: 0x57, 0x5E: 0x58, 0x5F: 0x59, 0x60: 0x5B, // KP 5-8
    0x61: 0x5C, 0x62: 0x52, 0x63: 0x41,              // KP 9, 0, .
]

func cgFlags(from mod: UInt8) -> CGEventFlags {
    var f = CGEventFlags()
    if mod & 0x01 != 0 { f.insert(.maskControl) }
    if mod & 0x02 != 0 { f.insert(.maskShift) }
    if mod & 0x04 != 0 { f.insert(.maskAlternate) }
    if mod & 0x08 != 0 { f.insert(.maskCommand) }
    if mod & 0x10 != 0 { f.insert(.maskControl) }
    if mod & 0x20 != 0 { f.insert(.maskShift) }
    if mod & 0x40 != 0 { f.insert(.maskAlternate) }
    if mod & 0x80 != 0 { f.insert(.maskCommand) }
    return f
}

// MARK: - Serial port

func findDonglePort() -> String? {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: "/dev") else { return nil }
    // ESP32-C3 enumerates as usbmodem on macOS
    let candidates = files.filter { $0.hasPrefix("cu.usbmodem") || $0.hasPrefix("cu.SLAB_USBtoUART") || $0.hasPrefix("cu.wchusbserial") }
    return candidates.first.map { "/dev/\($0)" }
}

func openSerial(_ path: String) -> Int32 {
    let fd = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK)
    guard fd >= 0 else { return -1 }
    var tty = termios()
    tcgetattr(fd, &tty)
    cfmakeraw(&tty)
    cfsetispeed(&tty, speed_t(B115200))
    cfsetospeed(&tty, speed_t(B115200))
    tcsetattr(fd, TCSANOW, &tty)
    // Switch back to blocking
    let flags = fcntl(fd, F_GETFL)
    _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
    return fd
}

// MARK: - Injection

var prevKeys = [UInt8](repeating: 0, count: 6)
var prevMod: UInt8 = 0
var prevButtons: UInt8 = 0
var mouseX: CGFloat = CGFloat(CGDisplayPixelsWide(CGMainDisplayID())) / 2
var mouseY: CGFloat = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID())) / 2

func injectKeyboard(modifier: UInt8, keys: [UInt8]) {
    usleep(200_000) // 200ms delay — proof the keystroke came via the dongle
    let flags = cgFlags(from: modifier)

    // Releases first to avoid stuck keys
    for k in prevKeys where k != 0 && !keys.contains(k) {
        guard let vk = hidToCGKey[k] else { continue }
        if let e = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: false) {
            e.flags = flags
            e.post(tap: .cgSessionEventTap)
        }
    }
    // Presses
    for k in keys where k != 0 && !prevKeys.contains(k) {
        guard let vk = hidToCGKey[k] else { continue }
        if let e = CGEvent(keyboardEventSource: nil, virtualKey: vk, keyDown: true) {
            e.flags = flags
            e.post(tap: .cgSessionEventTap)
        }
    }
    prevKeys = keys
    prevMod = modifier
}

func injectMouse(buttons: UInt8, dx: Int8, dy: Int8, scroll: Int8) {
    let w = CGFloat(CGDisplayPixelsWide(CGMainDisplayID()))
    let h = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
    mouseX = max(0, min(w - 1, mouseX + CGFloat(dx)))
    mouseY = max(0, min(h - 1, mouseY + CGFloat(dy)))
    let pos = CGPoint(x: mouseX, y: mouseY)

    if dx != 0 || dy != 0 {
        // Determine current pressed button for move events
        let moveType: CGEventType = (buttons & 0x01) != 0 ? .leftMouseDragged :
                                    (buttons & 0x02) != 0 ? .rightMouseDragged : .mouseMoved
        if let e = CGEvent(mouseEventSource: nil, mouseType: moveType, mouseCursorPosition: pos, mouseButton: .left) {
            e.post(tap: .cgSessionEventTap)
        }
    }

    // Button transitions
    let pressed  = buttons & ~prevButtons
    let released = prevButtons & ~buttons

    if pressed  & 0x01 != 0, let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,  mouseCursorPosition: pos, mouseButton: .left)  { e.post(tap: .cgSessionEventTap) }
    if released & 0x01 != 0, let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,    mouseCursorPosition: pos, mouseButton: .left)  { e.post(tap: .cgSessionEventTap) }
    if pressed  & 0x02 != 0, let e = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: pos, mouseButton: .right) { e.post(tap: .cgSessionEventTap) }
    if released & 0x02 != 0, let e = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp,   mouseCursorPosition: pos, mouseButton: .right) { e.post(tap: .cgSessionEventTap) }

    if scroll != 0, let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(scroll), wheel2: 0, wheel3: 0) {
        e.post(tap: .cgSessionEventTap)
    }

    prevButtons = buttons
}

// MARK: - Frame parser

func runReceiver(fd: Int32) {
    var buf = [UInt8]()
    buf.reserveCapacity(64)
    var readBuf = [UInt8](repeating: 0, count: 64)

    print("Connected — forwarding keystrokes. Press Ctrl+C to stop.")

    while true {
        let n = read(fd, &readBuf, 64)
        if n <= 0 { break }
        buf.append(contentsOf: readBuf[0..<n])

        // Parse all complete frames from buffer
        var idx = 0
        while idx < buf.count - 1 {
            // Sync: find 0xFE 0xFF
            if buf[idx] != 0xFE || buf[idx + 1] != 0xFF {
                idx += 1
                continue
            }
            guard idx + 2 < buf.count else { break }
            let type = buf[idx + 2]
            let frameLen: Int
            switch type {
            case 0x01: frameLen = 11
            case 0x02: frameLen = 7
            default: idx += 2; continue
            }
            guard idx + frameLen <= buf.count else { break }

            let frame = Array(buf[idx..<(idx + frameLen)])
            switch type {
            case 0x01:
                injectKeyboard(modifier: frame[3], keys: Array(frame[5...10]))
            case 0x02:
                injectMouse(buttons: frame[3], dx: Int8(bitPattern: frame[4]),
                            dy: Int8(bitPattern: frame[5]), scroll: Int8(bitPattern: frame[6]))
            default: break
            }
            idx += frameLen
        }
        buf = Array(buf[idx...])
    }
}

// MARK: - Main

if !AXIsProcessTrusted() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(opts)
    print("⚠️  Accessibility permission required.")
    print("   Grant access in System Settings → Privacy & Security → Accessibility,")
    print("   then re-run this program.")
    exit(1)
}

print("KB Dongle Receiver — waiting for dongle on USB...")
var fd: Int32 = -1
while fd < 0 {
    if let port = findDonglePort() {
        print("Found: \(port)")
        fd = openSerial(port)
    }
    if fd < 0 { Thread.sleep(forTimeInterval: 1) }
}

runReceiver(fd: fd)
close(fd)
print("Disconnected.")
