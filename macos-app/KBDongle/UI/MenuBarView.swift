import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var slotManager: SlotManager
    @EnvironmentObject var dongleManager: DongleManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: slotManager.activeSlot == 1 ? "keyboard" : "keyboard.fill")
                    .foregroundColor(slotManager.activeSlot == 1 ? .secondary : .accentColor)
                Text(slotManager.activeSlot == 1 ? "Local (CMD+Shift+1)" : "Remote — Slot \(slotManager.activeSlot)")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
            slotRow(slot: 1, label: "This Mac", systemImage: "laptopcomputer", isConnected: true)

            ForEach(Array(dongleManager.dongles.enumerated()), id: \.offset) { index, dongle in
                slotRow(slot: index + 2, label: dongle.displayName,
                        systemImage: "cable.connector", isConnected: dongle.isReady)
            }

            Divider()

            Button(dongleManager.isScanning ? "Scanning..." : "Scan for dongles") {
                if dongleManager.isScanning { dongleManager.stopScanning() }
                else { dongleManager.startScanning() }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(width: 260)
    }

    private func slotRow(slot: Int, label: String, systemImage: String, isConnected: Bool) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(isConnected ? .green : .secondary).frame(width: 16)
            Text("CMD+Shift+\(slot)  \(label)")
                .font(.system(.body, design: .monospaced))
            Spacer()
            if slotManager.activeSlot == slot {
                Image(systemName: "checkmark").foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { slotManager.switchTo(slot: slot) }
        .background(slotManager.activeSlot == slot ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}
