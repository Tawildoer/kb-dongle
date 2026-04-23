import Foundation
import CoreGraphics
import Carbon

final class KeyInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let reportBuilder = HIDReportBuilder()

    var onKeyReport: (([UInt8]) -> Void)?
    var onMouseReport: (([UInt8]) -> Void)?
    var onSlotSwitch: ((Int) -> Void)?
    var isRemoteActive = false

    func start() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        installTap()
    }

    private func installTap() {
        let mask: CGEventMask = [
            CGEventType.keyDown, .keyUp,
            .mouseMoved, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .scrollWheel
        ].reduce(0) { $0 | (1 << $1.rawValue) }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                let interceptor = Unmanaged<KeyInterceptor>
                    .fromOpaque(refcon!).takeUnretainedValue()
                return interceptor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )
        guard let tap = eventTap else { return }
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType,
                        event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown, .keyUp:
            return handleKey(event: event, isDown: type == .keyDown)
        case .mouseMoved, .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp:
            return handleMouse(event: event, type: type)
        case .scrollWheel:
            return handleScroll(event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKey(event: CGEvent, isDown: Bool) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if isDown && flags.contains(.maskCommand) && flags.contains(.maskShift) {
            let slotKeys: [CGKeyCode: Int] = [
                0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4,
                0x17: 5, 0x16: 6, 0x1A: 7, 0x1C: 8, 0x19: 9,
            ]
            if let slot = slotKeys[keyCode] {
                onSlotSwitch?(slot)
                return nil
            }
        }
        guard isRemoteActive else { return Unmanaged.passUnretained(event) }
        let report = isDown
            ? reportBuilder.keyDown(cgKeyCode: keyCode, flags: flags)
            : reportBuilder.keyUp(cgKeyCode: keyCode, flags: flags)
        onKeyReport?(report)
        return nil
    }

    private func handleMouse(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        guard isRemoteActive else { return Unmanaged.passUnretained(event) }
        var buttons: UInt8 = 0
        if type == .leftMouseDown  { buttons |= 0x01 }
        if type == .rightMouseDown { buttons |= 0x02 }
        let dx = clampToInt8(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = clampToInt8(event.getIntegerValueField(.mouseEventDeltaY))
        let report = HIDReportBuilder.mouseReport(buttons: buttons, dx: dx, dy: dy, scroll: 0)
        onMouseReport?(report)
        return nil
    }

    private func handleScroll(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isRemoteActive else { return Unmanaged.passUnretained(event) }
        let scroll = clampToInt8(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let report = HIDReportBuilder.mouseReport(buttons: 0, dx: 0, dy: 0, scroll: scroll)
        onMouseReport?(report)
        return nil
    }
}

private func clampToInt8(_ value: Int64) -> Int8 {
    let clamped = Swift.max(Int64(Int8.min), Swift.min(Int64(Int8.max), value))
    return Int8(clamped)
}
