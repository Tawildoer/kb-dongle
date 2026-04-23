import SwiftUI

@main
struct KBDongleApp: App {
    @StateObject private var dongleManager = DongleManager()
    @StateObject private var slotManager = SlotManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(slotManager)
                .environmentObject(dongleManager)
        } label: {
            Image(systemName: slotManager.activeSlot == 1 ? "keyboard" : "keyboard.fill")
        }
        .menuBarExtraStyle(.window)
        .onChange(of: dongleManager.dongles.count) { _ in
            slotManager.dongleManager = dongleManager
        }
    }
}
