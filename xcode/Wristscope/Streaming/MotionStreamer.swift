//  MotionStreamer.swift
//
//  Forwards byte batches from the iPhone to a computer over TCP, byte-for-byte.
//  Pair with the Wristscope desktop app (`wristscope`), which listens on port 9000.
//
//  Usage:
//      let streamer = MotionStreamer()
//      streamer.onStatus = { print($0) }            // optional, called on the main thread
//      streamer.discover()                          // find the receiver via Bonjour…
//      // streamer.connect(host: "192.168.1.20")    // …or give its IP directly
//
//      // wherever your ~100 ms batches arrive, on any thread:
//      streamer.send(batch)                         // Data, [UInt8], or any UInt8 buffer
//
//      streamer.stop()
//
//  Wire format: one frame per send() call, integers big-endian.
//      UInt32   payload length in bytes
//      UInt32   sequence number, +1 per send() call (batches dropped while
//               disconnected still use a number, so the receiver sees the gap)
//      Float64  phone's Unix time when send() was called
//      bytes    the payload, exactly as passed to send()
//
//  Info.plist:
//      NSLocalNetworkUsageDescription   e.g. "Sends sensor data to your computer."
//      NSBonjourServices                array containing "_motionstream._tcp" (needed for discover())

import Foundation
import Network

nonisolated final class MotionStreamer: @unchecked Sendable {

    static let serviceType = "_motionstream._tcp"

    /// Status messages for your UI, delivered on the main thread.
    var onStatus: (@MainActor (String) -> Void)?

    private enum Mode { case fixed(NWEndpoint), bonjour }

    private let maxInFlight: Int
    private let queue = DispatchQueue(label: "MotionStreamer")

    // Touched only on `queue`.
    private var mode: Mode?
    private var generation = 0            // bumped on connect/discover/stop/retry to cancel stale retries
    private var connection: NWConnection?
    private var browser: NWBrowser?
    private var seq: UInt32 = 0
    private var inFlight = 0

    /// - Parameter maxInFlight: batches allowed to wait on a slow network before new ones are
    ///   dropped instead of queued, so the stream stays live rather than falling further and
    ///   further behind. The receiver sees drops as a sequence gap. 5 ≈ 0.5 s of 100 ms batches.
    init(maxInFlight: Int = 5) {
        self.maxInFlight = max(1, maxInFlight)
    }

    // MARK: - Connecting

    /// Send to a fixed address (Wristscope prints its IP when it starts).
    func connect(host: String, port: UInt16 = 9000) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        queue.async {
            self.generation += 1
            self.mode = .fixed(endpoint)
            self.open(endpoint)
        }
    }

    /// Find the Wristscope desktop app on the local network via Bonjour. Reconnects automatically,
    /// including after the receiver restarts.
    func discover() {
        queue.async {
            self.generation += 1
            self.mode = .bonjour
            self.browse()
        }
    }

    /// Disconnect and stop reconnecting.
    func stop() {
        queue.async {
            self.generation += 1
            self.mode = nil
            self.closeAll()
            self.status("Stopped")
        }
    }

    // MARK: - Sending

    /// Queue one batch. Safe to call from any thread; returns immediately.
    func send(_ data: Data) {
        let time = Date().timeIntervalSince1970
        queue.async { self.enqueue(data, time: time) }
    }

    /// Same as send(_: Data), for [UInt8], ArraySlice<UInt8>, UnsafeBufferPointer<UInt8>, etc.
    func send<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        send(Data(bytes))
    }

    private func enqueue(_ payload: Data, time: Double) {
        let thisSeq = seq
        seq &+= 1

        // Not connected, or the network is backed up: drop this batch rather than build a backlog.
        guard let conn = connection, case .ready = conn.state, inFlight < maxInFlight else { return }

        var frame = Data(capacity: 16 + payload.count)
        Self.append(UInt32(payload.count), to: &frame)
        Self.append(thisSeq, to: &frame)
        Self.append(time.bitPattern, to: &frame)
        frame.append(payload)

        inFlight += 1
        conn.send(content: frame, completion: .contentProcessed { [weak self, weak conn] _ in
            guard let self, let conn, conn === self.connection else { return }   // runs on `queue`
            self.inFlight -= 1
        })
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    // MARK: - Connection management (all on `queue`)

    private func browse() {
        closeAll()
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, let browser, self.browser === browser, let found = results.first else { return }
            self.open(found.endpoint)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state { self?.status("Discovery failed: \(error)") }
        }
        self.browser = browser
        status("Looking for the receiver…")
        browser.start(queue: queue)
    }

    private func open(_ endpoint: NWEndpoint) {
        closeAll()
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true                // send each batch immediately, don't coalesce
        tcp.connectionTimeout = 5
        tcp.enableKeepalive = true        // notice a vanished computer within a few seconds
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 3

        let conn = NWConnection(to: endpoint, using: NWParameters(tls: nil, tcp: tcp))
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.connection else { return }
            switch state {
            case .ready:
                self.status("Streaming to \(endpoint)")
                self.watchForClose(conn)
            case .waiting(let error), .failed(let error):
                self.status("Can't reach the receiver (\(error)), retrying…")
                self.scheduleReconnect()
            default:
                break
            }
        }
        connection = conn
        conn.start(queue: queue)
    }

    /// The receiver never sends anything, so a completed receive means it closed the connection.
    private func watchForClose(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak conn] _, _, isComplete, error in
            guard let self, let conn, conn === self.connection else { return }
            if isComplete || error != nil {
                self.status("Receiver disconnected, reconnecting…")
                self.scheduleReconnect()
            } else {
                self.watchForClose(conn)
            }
        }
    }

    private func scheduleReconnect() {
        closeAll()
        generation += 1
        let gen = generation
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generation == gen else { return }
            switch self.mode {
            case .fixed(let endpoint): self.open(endpoint)
            case .bonjour:             self.browse()       // re-browse in case the receiver's name changed
            case nil:                  break
            }
        }
    }

    private func closeAll() {
        browser?.cancel(); browser = nil
        connection?.cancel(); connection = nil
        inFlight = 0
    }

    private func status(_ message: String) {
        Task { @MainActor in self.onStatus?(message) }
    }
}
