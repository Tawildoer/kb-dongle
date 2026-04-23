import Foundation
import CoreBluetooth

final class DonglePeripheral: NSObject, ObservableObject, CBPeripheralDelegate {
    static let serviceUUID   = CBUUID(string: "a8b5e8d0-1c3a-11ee-be56-0242ac120002")
    static let keyCharUUID   = CBUUID(string: "a8b5e8d1-1c3a-11ee-be56-0242ac120002")
    static let mouseCharUUID = CBUUID(string: "a8b5e8d2-1c3a-11ee-be56-0242ac120002")

    let peripheral: CBPeripheral
    @Published var isReady = false
    var displayName: String

    private var keyChar: CBCharacteristic?
    private var mouseChar: CBCharacteristic?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.displayName = peripheral.name ?? "Unknown Dongle"
        super.init()
        peripheral.delegate = self
    }

    func discoverServices() {
        peripheral.discoverServices([DonglePeripheral.serviceUUID])
    }

    func sendKeyReport(_ report: [UInt8]) {
        guard let char = keyChar, isReady else { return }
        peripheral.writeValue(Data(report), for: char, type: .withoutResponse)
    }

    func sendMouseReport(_ report: [UInt8]) {
        guard let char = mouseChar, isReady else { return }
        peripheral.writeValue(Data(report), for: char, type: .withoutResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == DonglePeripheral.serviceUUID }) else { return }
        peripheral.discoverCharacteristics([DonglePeripheral.keyCharUUID, DonglePeripheral.mouseCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == DonglePeripheral.keyCharUUID   { keyChar = char }
            if char.uuid == DonglePeripheral.mouseCharUUID { mouseChar = char }
        }
        isReady = keyChar != nil && mouseChar != nil
    }
}
