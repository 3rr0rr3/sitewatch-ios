import Foundation
import SwiftUI

@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var inventory = Inventory()
    @Published private(set) var states: [String: DeviceState] = [:]
    @Published private(set) var events: [Event] = []
    @Published private(set) var running = false
    @Published var error: String?
    private var failures: [String: Int] = [:]
    private var revision = 0
    private let folder: URL
    private var inventoryURL: URL { folder.appendingPathComponent("devices.json") }
    private var eventsURL: URL { folder.appendingPathComponent("events.json") }

    init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            if FileManager.default.fileExists(atPath: inventoryURL.path) {
                inventory = try decode(Data(contentsOf: inventoryURL))
            }
            if FileManager.default.fileExists(atPath: eventsURL.path) {
                events = try JSONDecoder().decode([Event].self, from: Data(contentsOf: eventsURL))
            }
        } catch { self.error = "No se pudieron cargar los datos: \(error.localizedDescription). El archivo no se sobrescribió." }
    }

    private func decode(_ data: Data) throws -> Inventory {
        guard data.count <= 5_000_000 else { throw InventoryError.invalid("Archivo demasiado grande (máximo 5 MB).") }
        let decoder = JSONDecoder()
        let value: Inventory
        if let array = try? decoder.decode([Device].self, from: data) {
            var imported = Inventory(); imported.devices = array; value = imported
        } else { value = try decoder.decode(Inventory.self, from: data) }
        try Topology.validate(value)
        return value
    }

    private func commit(_ value: Inventory) throws {
        try Topology.validate(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: inventoryURL, options: .atomic)
        inventory = value
        revision += 1
    }

    func upsert(_ device: Device) throws {
        var next = inventory
        if let index = next.devices.firstIndex(where: { $0.id == device.id }) { next.devices[index] = device }
        else { next.devices.append(device) }
        try commit(next)
        states.removeValue(forKey: device.id)
        failures.removeValue(forKey: device.id)
    }

    func remove(_ device: Device) throws {
        guard !inventory.devices.contains(where: { $0.parent == device.id }) else {
            throw InventoryError.invalid("Primero cambia los uplinks que apuntan a este equipo.")
        }
        var next = inventory
        next.devices.removeAll { $0.id == device.id }
        if next.start == device.id { next.start = "" }
        try commit(next)
        states.removeValue(forKey: device.id)
        failures.removeValue(forKey: device.id)
    }

    func selectStart(_ id: String) {
        do { var next = inventory; next.start = id; try commit(next) }
        catch { self.error = error.localizedDescription }
    }

    func importFile(_ url: URL) throws {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let value = try decode(Data(contentsOf: url))
        try commit(value)
        states = [:]; failures = [:]
    }

    func exportData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(inventory)
    }

    func status(_ device: Device) -> DeviceState {
        device.ip.isEmpty ? .unmanaged : (states[device.id] ?? .waiting)
    }

    func beginSession() {
        revision += 1
        states = [:]
        failures = [:]
    }

    func check() async {
        guard !running, !Task.isCancelled else { return }
        running = true
        defer { running = false }
        let generation = revision
        let devices = inventory.devices.filter { !$0.ip.isEmpty }
        // Bound concurrency rather than opening a connection for every inventory entry.
        for offset in stride(from: 0, to: devices.count, by: 12) {
            guard !Task.isCancelled, generation == revision else { return }
            let groupDevices = Array(devices[offset..<min(offset + 12, devices.count)])
            let results = await withTaskGroup(of: (String, Bool).self) { group in
                for device in groupDevices {
                    group.addTask { (device.id, await TCPProbe.check(ip: device.ip, port: device.tcpPort)) }
                }
                var results: [(String, Bool)] = []
                for await value in group { results.append(value) }
                return results
            }
            guard !Task.isCancelled, generation == revision else { return }
            for (id, reachable) in results {
                failures[id] = reachable ? 0 : (failures[id, default: 0] + 1)
                let state: DeviceState = reachable ? .reachable : (failures[id, default: 0] >= 3 ? .noResponse : .checking)
                let previous = states[id]
                states[id] = state
                if previous != state, state == .reachable || state == .noResponse,
                   let device = inventory.devices.first(where: { $0.id == id }) {
                    events.insert(Event(message: "\(device.site) / \(device.name): \(state.rawValue) — puerto \(device.tcpPort)"), at: 0)
                }
            }
        }
        events = Array(events.prefix(500))
        do { try JSONEncoder().encode(events).write(to: eventsURL, options: .atomic) }
        catch { self.error = "No se pudo guardar el historial: \(error.localizedDescription)" }
    }
}
