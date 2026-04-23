import Foundation
import CoreBluetooth

final class DongleManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var dongles: [DonglePeripheral] = []
    @Published var isScanning = false

    private var central: CBCentralManager!
    private let btQueue = DispatchQueue(label: "com.specter.kbdongle.bt")
    private var connectingPeripheral: CBPeripheral?
    private var connectTimer: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: btQueue)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        DispatchQueue.main.async { self.isScanning = true }
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() { central.stopScan(); DispatchQueue.main.async { self.isScanning = false } }

    func dongle(atSlot slot: Int) -> DonglePeripheral? {
        let index = slot - 2
        guard index >= 0 && index < dongles.count else { return nil }
        return dongles[index]
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let stateNames = [0:"unknown",1:"resetting",2:"unsupported",3:"unauthorized",4:"poweredOff",5:"poweredOn"]
        let msg = "CBManager state: \(stateNames[central.state.rawValue] ?? "\(central.state.rawValue)")\n"
        try? (msg as NSString).write(toFile: "/tmp/kbdongle-bt-state.log", atomically: false, encoding: String.Encoding.utf8.rawValue)
        if central.state == .poweredOn { startScanning() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "<nil>"
        let entry = "didDiscover: \(name) rssi=\(RSSI)\n"
        if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") {
            fh.seekToEndOfFile(); fh.write(Data(entry.utf8)); fh.closeFile()
        }
        guard name.hasPrefix("KBDongle-") else { return }
        let stateMap = [0:"disconnected",1:"connecting",2:"connected",3:"disconnecting"]
        let pstate = stateMap[peripheral.state.rawValue] ?? "\(peripheral.state.rawValue)"
        let entry2 = "  -> peripheral.state=\(pstate), dongles.count=\(dongles.count)\n"
        if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") { fh.seekToEndOfFile(); fh.write(Data(entry2.utf8)); fh.closeFile() }
        guard !dongles.contains(where: { $0.peripheral == peripheral }) else { return }
        if peripheral.state == .disconnected {
            stopScanning()
            connectingPeripheral = peripheral
            central.connect(peripheral, options: nil)
            let msg2 = "  -> called connect(), id=\(peripheral.identifier)\n"
            if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") { fh.seekToEndOfFile(); fh.write(Data(msg2.utf8)); fh.closeFile() }
            scheduleConnectRetry(for: peripheral)
        }
    }

    private func scheduleConnectRetry(for peripheral: CBPeripheral) {
        connectTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let msg = "connect timeout — cancelling and retrying\n"
            if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") { fh.seekToEndOfFile(); fh.write(Data(msg.utf8)); fh.closeFile() }
            self.central.cancelPeripheralConnection(peripheral)
            self.connectingPeripheral = nil
            self.startScanning()
        }
        connectTimer = item
        btQueue.asyncAfter(deadline: .now() + 20, execute: item)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimer?.cancel(); connectTimer = nil; connectingPeripheral = nil
        let msg = "didConnect: \(peripheral.name ?? peripheral.identifier.uuidString)\n"
        try? msg.write(toFile: "/tmp/kbdongle-connected.txt", atomically: true, encoding: .utf8)
        if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") { fh.seekToEndOfFile(); fh.write(Data(msg.utf8)); fh.closeFile() }
        let dongle = DonglePeripheral(peripheral: peripheral)
        dongle.discoverServices()
        DispatchQueue.main.async { self.dongles.append(dongle) }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = "didFailToConnect: \(peripheral.name ?? peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "nil")\n"
        if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") { fh.seekToEndOfFile(); fh.write(Data(msg.utf8)); fh.closeFile() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let msg = "didDisconnect: \(peripheral.name ?? peripheral.identifier.uuidString) error=\(error?.localizedDescription ?? "nil")\n"
        if let fh = FileHandle(forWritingAtPath: "/tmp/kbdongle-bt-state.log") { fh.seekToEndOfFile(); fh.write(Data(msg.utf8)); fh.closeFile() }
        DispatchQueue.main.async { self.dongles.removeAll { $0.peripheral == peripheral } }
        central.connect(peripheral, options: nil)
        startScanning()
    }
}
