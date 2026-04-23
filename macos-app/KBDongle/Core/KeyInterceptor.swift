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

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?

    func start() {
        registerHotKeys()
        if AXIsProcessTrusted() {
            installTap()
        } else {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            pollForAccessibility()
        }
    }

    private func registerHotKeys() {
        // Carbon hotkeys work without Accessibility permission
        let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25] // 1–9
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, refcon -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, UInt32(kEventParamDirectObject),
                              UInt32(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
            interceptor.onSlotSwitch?(Int(hkID.id))
            return noErr
        }, 1, &eventType, selfPtr, &hotKeyHandler)

        for (i, keyCode) in keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4B424B59), id: UInt32(i + 1))
            RegisterEventHotKey(keyCode,
                                UInt32(cmdKey | shiftKey),
                                id, GetApplicationEventTarget(), 0, &ref)
            if let ref { hotKeyRefs.append(ref) }
        }
    }

    private func pollForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            if AXIsProcessTrusted() { self.installTap() }
            else { self.pollForAccessibility() }
        }
    }

    private func installTap() {
        try? "tap installing\n".write(toFile: "/tmp/kbdongle-ax.log", atomically: true, encoding: .utf8)
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
        guard let tap = eventTap else {
            try? "tap creation FAILED\n".write(toFile: "/tmp/kbdongle-ax.log", atomically: true, encoding: .utf8)
            return
        }
        try? "tap created OK\n".write(toFile: "/tmp/kbdongle-ax.log", atomically: true, encoding: .utf8)
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
        // Slot switching is handled by Carbon hotkeys — suppress CMD+Shift+1-9 from forwarding
        if isDown && flags.contains(.maskCommand) && flags.contains(.maskShift) {
            let slotKeyCodes: Set<CGKeyCode> = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
            if slotKeyCodes.contains(keyCode) { return Unmanaged.passUnretained(event) }
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
