import Foundation
import CoreBluetooth

final class DongleManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var dongles: [DonglePeripheral] = []
    @Published var isScanning = false

    private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        isScanning = true
        central.scanForPeripherals(withServices: [DonglePeripheral.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() { central.stopScan(); isScanning = false }

    func dongle(atSlot slot: Int) -> DonglePeripheral? {
        let index = slot - 2
        guard index >= 0 && index < dongles.count else { return nil }
        return dongles[index]
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard peripheral.name?.hasPrefix("KBDongle-") == true else { return }
        guard !dongles.contains(where: { $0.peripheral == peripheral }) else { return }
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let dongle = DonglePeripheral(peripheral: peripheral)
        DispatchQueue.main.async { self.dongles.append(dongle) }
        dongle.discoverServices()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { self.dongles.removeAll { $0.peripheral == peripheral } }
        central.connect(peripheral, options: nil)
    }
}
