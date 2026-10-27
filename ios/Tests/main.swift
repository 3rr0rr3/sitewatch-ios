import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
var a = Device(); a.id = "a"; a.name = "A"; a.site = "Sede"; a.ip = "192.168.2.2"; a.parent = "b"
var b = Device(); b.id = "b"; b.name = "B"; b.site = "Sede"; b.parent = "c"
var c = Device(); c.id = "c"; c.name = "C"; c.site = "Sede"; c.ip = "172.17.21.2"
var inventory = Inventory(); inventory.devices = [a,b,c]; inventory.start = "a"
try Topology.validate(inventory)
let route = try Topology.route(inventory, from: "a")
expect(route.map(\.id) == ["a","b","c"], "Incorrect order")
let report = Diagnosis.report(route: route, states: ["a": .reachable, "c": .noResponse])
expect(report.contains("A → C"), "Incorrect boundary")
expect(report.contains("no se puede aislar uno solo"), "Unmanaged gap must remain uncertain")
expect(!Diagnosis.report(route: route, states: [:]).contains("Tramo por revisar"), "No evidence must not imply outage")
expect(Topology.isIPv4("192.168.2.1"), "Valid IPv4 rejected")
expect(!Topology.isIPv4("192.168.2.999"), "Invalid IPv4 accepted")
inventory.devices[2].parent = "a"
do { try Topology.validate(inventory); fatalError("Cycle accepted") } catch is InventoryError {}
inventory.devices[2].parent = "missing"
do { try Topology.validate(inventory); fatalError("Missing parent accepted") } catch is InventoryError {}
let legacy = Data("{\"devices\":[{\"id\":\"old\",\"site\":\"A\",\"name\":\"Old\",\"uplink\":\"port 24\"}]}".utf8)
let imported = try JSONDecoder().decode(Inventory.self, from: legacy)
expect(imported.devices[0].ports == "port 24", "Legacy description lost")
expect(imported.devices[0].tcpPort == 443, "Default port incorrect")
let roundTrip = try JSONDecoder().decode(Inventory.self, from: JSONEncoder().encode(imported))
expect(roundTrip.devices == imported.devices, "Round trip changed inventory")
print("Topology, uncertainty, IPv4 validation, cycle rejection and Windows JSON compatibility passed")
