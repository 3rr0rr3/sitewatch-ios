import Foundation
import Network

// No raw sockets, packet capture, broadcast, or private entitlements.
final class TCPProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private var continuation: CheckedContinuation<Bool, Never>?
    private var connection: NWConnection?
    private var deadline: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.sitewatch.tcp.\(UUID().uuidString)")

    static func check(ip: String, port: UInt16) async -> Bool {
        guard Topology.isIPv4(ip), let endpoint = NWEndpoint.Port(rawValue: port) else { return false }
        let probe = TCPProbe()
        return await withCheckedContinuation { continuation in
            probe.continuation = continuation
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: endpoint, using: .tcp)
            probe.connection = connection
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: probe.finish(true)
                case .failed, .cancelled: probe.finish(false)
                default: break
                }
            }
            let deadline = DispatchWorkItem { probe.finish(false) }
            probe.deadline = deadline
            probe.queue.asyncAfter(deadline: .now() + 3, execute: deadline)
            connection.start(queue: probe.queue)
        }
    }

    private func finish(_ result: Bool) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let continuation = self.continuation
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        let deadline = self.deadline
        self.deadline = nil
        lock.unlock()
        deadline?.cancel()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        continuation?.resume(returning: result)
    }
}
