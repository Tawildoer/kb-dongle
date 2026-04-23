import Foundation
import Combine

final class SlotManager: ObservableObject {
    @Published var activeSlot: Int = 1
    let interceptor = KeyInterceptor()
    var dongleManager: DongleManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        interceptor.onSlotSwitch = { [weak self] slot in
            DispatchQueue.main.async { self?.switchTo(slot: slot) }
        }
        interceptor.onKeyReport = { [weak self] report in self?.forwardKey(report) }
        interceptor.onMouseReport = { [weak self] report in self?.forwardMouse(report) }
        interceptor.start()
    }

    func switchTo(slot: Int) {
        activeSlot = slot
        interceptor.isRemoteActive = slot > 1
        let name = dongleManager?.dongle(atSlot: slot)?.displayName ?? "Dongle \(slot)"
        SlotHUD.shared.show(slot: slot, name: name)
    }

    private func forwardKey(_ report: [UInt8]) {
        dongleManager?.dongle(atSlot: activeSlot)?.sendKeyReport(report)
    }

    private func forwardMouse(_ report: [UInt8]) {
        dongleManager?.dongle(atSlot: activeSlot)?.sendMouseReport(report)
    }
}
