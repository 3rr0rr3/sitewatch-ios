import SwiftUI
import UniformTypeIdentifiers

@main
struct SiteWatchApp: App {
    @StateObject private var monitor = Monitor()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(monitor).tint(.cyan) }
    }
}

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct RootView: View {
    @EnvironmentObject var monitor: Monitor
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            EquipmentView().tabItem { Label("Equipos", systemImage: "network") }
            RouteView().tabItem { Label("Ruta", systemImage: "point.3.connected.trianglepath.dotted") }
            NavigationStack {
                List {
                    if monitor.events.isEmpty { Text("Todavía no hay eventos. Comprueba tus equipos para iniciar el historial.").foregroundStyle(.secondary) }
                    ForEach(monitor.events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.message)
                            Text(event.date, format: .dateTime.day().month().hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.navigationTitle("Historial")
            }.tabItem { Label("Historial", systemImage: "clock.arrow.circlepath") }
            SettingsView().tabItem { Label("Datos", systemImage: "folder") }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            monitor.beginSession()
            while !Task.isCancelled {
                await monitor.check()
                do { try await Task.sleep(nanoseconds: 10_000_000_000) }
                catch { return }
            }
        }
        .alert("SiteWatch", isPresented: Binding(get: { monitor.error != nil }, set: { if !$0 { monitor.error = nil } })) {
            Button("Aceptar") { monitor.error = nil }
        } message: { Text(monitor.error ?? "") }
    }
}

struct StatusBadge: View {
    let state: DeviceState
    private var color: Color {
        switch state { case .reachable: return .green; case .noResponse: return .orange; default: return .secondary }
    }
    var body: some View {
        Label(state.rawValue, systemImage: state == .reachable ? "checkmark.circle.fill" : "circle.dotted")
            .font(.caption).foregroundStyle(color)
    }
}

struct EquipmentView: View {
    @EnvironmentObject var monitor: Monitor
    @State private var editing: Device?
    @State private var search = ""
    var sites: [String] { Array(Set(monitor.inventory.devices.map(\.site))).sorted() }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Tu red, por ubicación", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                        Text("\(sites.count) sedes · \(monitor.inventory.devices.count) equipos registrados")
                        Text("Conexiones manuales · Comprobaciones TCP en primer plano").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                if monitor.inventory.devices.isEmpty {
                    Section {
                        Text("Agrega tus switches y routers o importa devices.json desde la versión de Windows.")
                        Button("Agregar primer equipo") { editing = Device() }
                    }
                }
                ForEach(sites, id: \.self) { site in
                    Section(site) {
                        ForEach(monitor.inventory.devices.filter {
                            $0.site == site && (search.isEmpty || ($0.name + " " + $0.ip + " " + $0.site).localizedCaseInsensitiveContains(search))
                        }) { device in
                            Button { editing = device } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "server.rack").font(.title2).foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(device.name).font(.headline).foregroundStyle(.primary)
                                        Text(device.ip.isEmpty ? "Sin IP de gestión" : "\(device.ip):\(device.tcpPort)")
                                            .font(.caption).foregroundStyle(.secondary)
                                        StatusBadge(state: monitor.status(device))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                            .swipeActions {
                                Button("Eliminar", role: .destructive) {
                                    do { try monitor.remove(device) } catch { monitor.error = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SiteWatch")
            .searchable(text: $search, prompt: "Nombre, sede o IP")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await monitor.check() } } label: {
                        if monitor.running { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }.disabled(monitor.running).accessibilityLabel("Comprobar equipos")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { editing = Device() } label: { Image(systemName: "plus") }.accessibilityLabel("Agregar equipo") }
            }
            .sheet(item: $editing) { DeviceEditor(device: $0) }
        }
    }
}

struct DeviceEditor: View {
    @EnvironmentObject var monitor: Monitor
    @Environment(\.dismiss) private var dismiss
    @State var device: Device
    @State private var port = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Identificación") {
                    TextField("Sede", text: $device.site)
                    TextField("Nombre", text: $device.name)
                    TextField("Tipo / modelo", text: $device.type)
                }
                Section {
                    TextField("IP de gestión (opcional)", text: $device.ip).keyboardType(.decimalPad)
                    TextField("Puerto TCP", text: $port).keyboardType(.numberPad)
                } header: { Text("Comprobación") } footer: {
                    Text("Usa un puerto de gestión conocido y habilitado, por ejemplo HTTPS 443 o SSH 22. Un puerto cerrado o filtrado no significa que el switch esté apagado. Sin IP: inventario manual.")
                }
                Section {
                    Picker("Uplink hacia", selection: $device.parent) {
                        Text("Sin registrar").tag("")
                        ForEach(monitor.inventory.devices.filter { $0.id != device.id }) { other in
                            Text("\(other.site) / \(other.name)").tag(other.id)
                        }
                    }
                    TextField("Puerto local → puerto remoto", text: $device.ports)
                } header: { Text("Conexión registrada") } footer: { Text("La app no descubre ni verifica estos enlaces automáticamente.") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle("Equipo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let number = UInt16(port), number > 0 else { error = "Puerto inválido (1–65535)."; return }
                        device.tcpPort = number
                        device.name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        device.site = device.site.trimmingCharacters(in: .whitespacesAndNewlines)
                        device.ip = device.ip.trimmingCharacters(in: .whitespacesAndNewlines)
                        do { try monitor.upsert(device); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
            }.onAppear { port = String(device.tcpPort) }
        }
    }
}

struct RouteView: View {
    @EnvironmentObject var monitor: Monitor
    private var route: [Device] { (try? Topology.route(monitor.inventory, from: monitor.inventory.start)) ?? [] }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Switch de origen", selection: Binding(get: { monitor.inventory.start }, set: monitor.selectStart)) {
                        Text("Seleccionar").tag("")
                        ForEach(monitor.inventory.devices) { device in Text("\(device.site) / \(device.name)").tag(device.id) }
                    }
                    Text("Selecciona el switch conectado a tu punto de acceso Wi-Fi o adaptador Ethernet. No se detecta automáticamente.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Cadena de uplinks registrada") {
                    Label("iPhone / conexión de acceso", systemImage: "iphone")
                    ForEach(route) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(device.site) / \(device.name)", systemImage: "arrow.down.right")
                            StatusBadge(state: monitor.status(device))
                            Text("Uplink: \(device.ports.isEmpty ? "puertos sin registrar" : device.ports)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }
                }
                Section("Diagnóstico orientativo") { Text(Diagnosis.report(route: route, states: monitor.states)).font(.callout) }
                Section { Text("TCP confirma que un servicio acepta conexiones, no el estado físico del enlace. No confirma internet ni alimentación eléctrica. Integración SNMP/LLDP y FortiGate pendiente.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Ruta de conexión")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var monitor: Monitor
    @State private var importing = false
    @State private var exporting = false
    @State private var confirmImport = false
    @State private var document = JSONDocument()
    var body: some View {
        NavigationStack {
            Form {
                Section("Inventario compartido con Windows") {
                    Button("Importar devices.json") { confirmImport = true }
                    Button("Exportar inventario") {
                        do { document = JSONDocument(data: try monitor.exportData()); exporting = true }
                        catch { monitor.error = error.localizedDescription }
                    }
                    Text("Importar reemplaza el inventario de este iPhone. Exporta una copia primero. La versión Windows conserva los campos comunes; los puertos TCP son propios de iOS.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Funcionamiento") {
                    Text("Permite el acceso a la red local cuando iOS lo solicite.")
                    Text("Las pruebas se realizan al abrir la app y aproximadamente cada 10 segundos después de terminar cada ronda. Tres fallos consecutivos generan estado Sin respuesta TCP.")
                    Text("Al salir de la app, las pruebas se pausan y los estados se reinician al volver. Para monitoreo continuo usa un equipo siempre encendido.")
                    Text("Necesitas Wi-Fi o VPN con rutas hacia las IP de gestión. No se incluyen credenciales ni se envía tu inventario a un servidor de la app.")
                }
                Section("Versión inicial") {
                    Text("No incluye escaneo automático, consulta de puertos por SNMP, API FortiGate ni pruebas separadas de gateway/internet/DNS. Los estados de Windows usan ICMP; los de iOS usan TCP y no son equivalentes.")
                }
            }.navigationTitle("Datos y ayuda")
            .confirmationDialog("¿Reemplazar el inventario?", isPresented: $confirmImport, titleVisibility: .visible) {
                Button("Seleccionar archivo para reemplazar", role: .destructive) { importing = true }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { try monitor.importFile(result.get()) } catch { monitor.error = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "devices") { result in
                if case .failure(let error) = result { monitor.error = error.localizedDescription }
            }
        }
    }
}
