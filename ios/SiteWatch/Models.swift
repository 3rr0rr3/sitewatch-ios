import Foundation

struct Device: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var site = ""
    var name = ""
    var type = "Switch"
    var ip = ""
    var parent = ""
    var ports = ""
    var tcpPort: UInt16 = 443

    enum CodingKeys: String, CodingKey { case id, site, name, type, ip, parent, ports, uplink, tcpPort }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        site = try c.decode(String.self, forKey: .site)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "Switch"
        ip = try c.decodeIfPresent(String.self, forKey: .ip) ?? ""
        parent = try c.decodeIfPresent(String.self, forKey: .parent) ?? ""
        ports = try c.decodeIfPresent(String.self, forKey: .ports) ?? c.decodeIfPresent(String.self, forKey: .uplink) ?? ""
        tcpPort = try c.decodeIfPresent(UInt16.self, forKey: .tcpPort) ?? 443
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(site, forKey: .site)
        try c.encode(name, forKey: .name)
        try c.encode(type, forKey: .type)
        try c.encode(ip, forKey: .ip)
        try c.encode(parent, forKey: .parent)
        try c.encode(ports, forKey: .ports)
        try c.encode(tcpPort, forKey: .tcpPort)
    }
}

struct Inventory: Codable {
    var devices: [Device] = []
    var start: String = ""
    enum CodingKeys: String, CodingKey { case devices, start }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        devices = try c.decode([Device].self, forKey: .devices)
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
    }
}

enum InventoryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum Topology {
    static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && UInt8($0) != nil
        }
    }

    static func route(_ inventory: Inventory, from start: String) throws -> [Device] {
        var result: [Device] = []
        var visited = Set<String>()
        var current = start
        while !current.isEmpty {
            guard visited.insert(current).inserted else {
                throw InventoryError.invalid("La conexión crea un ciclo de uplinks.")
            }
            guard let device = inventory.devices.first(where: { $0.id == current }) else {
                throw InventoryError.invalid("Un uplink apunta a un equipo inexistente.")
            }
            result.append(device)
            current = device.parent
        }
        return result
    }

    static func validate(_ inventory: Inventory) throws {
        guard inventory.devices.count <= 1000 else {
            throw InventoryError.invalid("El inventario admite hasta 1000 equipos.")
        }
        var ids = Set<String>()
        var names = Set<String>()
        for device in inventory.devices {
            guard !device.id.isEmpty, ids.insert(device.id).inserted else {
                throw InventoryError.invalid("Hay identificadores de equipo vacíos o duplicados.")
            }
            guard !device.site.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !device.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw InventoryError.invalid("Cada equipo necesita sede y nombre.")
            }
            let key = device.site + "\u{0}" + device.name
            guard names.insert(key).inserted else {
                throw InventoryError.invalid("Hay nombres duplicados en una sede.")
            }
            guard device.ip.isEmpty || isIPv4(device.ip), device.tcpPort > 0 else {
                throw InventoryError.invalid("Revisa las IP y los puertos TCP (1–65535).")
            }
            _ = try route(inventory, from: device.id)
        }
        if !inventory.start.isEmpty { _ = try route(inventory, from: inventory.start) }
    }
}

enum DeviceState: String {
    case waiting = "Pendiente"
    case reachable = "Puerto TCP accesible"
    case checking = "Comprobando"
    case noResponse = "Sin respuesta TCP"
    case unmanaged = "Sin gestión"
}

struct Event: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var message: String
}

enum Diagnosis {
    static func report(route: [Device], states: [String: DeviceState]) -> String {
        guard !route.isEmpty else { return "Selecciona el switch conectado a tu punto de acceso o adaptador Ethernet. La ruta se registra manualmente." }
        var lastGood = "iPhone"
        var gap = false
        for device in route {
            let state = device.ip.isEmpty ? DeviceState.unmanaged : (states[device.id] ?? .waiting)
            if state == .reachable { lastGood = device.name; gap = false }
            else if state == .noResponse {
                return "Tramo por revisar: \(lastGood) → \(device.name).\n\nEl puerto TCP configurado no respondió en tres comprobaciones. Puede ser equipo, cable, ruta de gestión, servicio cerrado o filtrado. No confirma apagado."
                    + (gap ? "\n\nHay equipos sin evidencia reciente en ese tramo; no se puede aislar uno solo." : "")
                    + "\n\nLos equipos posteriores pueden estar encendidos pero aislados. Las IP de gestión pueden seguir una ruta distinta al tráfico del iPhone."
            } else { gap = true }
        }
        return "No hay fallas TCP persistentes detectadas en la ruta registrada. Esto no verifica todos los enlaces ni confirma acceso a internet. Los equipos sin gestión siguen sin comprobarse."
    }
}
