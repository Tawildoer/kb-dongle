import AppKit
import SwiftUI

final class SlotHUD {
    static let shared = SlotHUD()
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(slot: Int, name: String) {
        DispatchQueue.main.async { self._show(slot: slot, name: name) }
    }

    private func _show(slot: Int, name: String) {
        hideWorkItem?.cancel()

        let hostingView = NSHostingView(rootView: HUDView(slot: slot, name: name))
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 80)

        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sw = screen.frame.width
        let sh = screen.frame.height
        panel!.setFrame(NSRect(x: (sw - 280) / 2, y: sh * 0.72, width: 280, height: 80), display: false)
        panel!.contentView = hostingView
        panel!.alphaValue = 0
        panel!.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel!.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }
}

private struct HUDView: View {
    let slot: Int
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.75))

            VStack(spacing: 6) {
                Image(systemName: slot == 1 ? "laptopcomputer" : "cable.connector")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                Text(slot == 1 ? "Local — This Mac" : "Remote — \(name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 280, height: 80)
    }
}
