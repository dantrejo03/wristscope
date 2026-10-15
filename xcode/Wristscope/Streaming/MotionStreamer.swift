//  MotionStreamer.swift
//
//  Forwards byte batches from the iPhone to a computer over USB, byte-for-byte.
//  Pair with the Wristscope desktop app (`wristscope`), which connects to port 9000.
//
//  Usage:
//      let streamer = MotionStreamer()
//      streamer.onStatus = { print($0) }            // optional, called on the main thread
//      streamer.listen()                            // wait for the computer to connect
//
//      // wherever your ~100 ms batches arrive, on any thread:
//      streamer.send(batch)                         // Data, [UInt8], or any UInt8 buffer
//
//      streamer.stop()
//
//  How the computer gets here: macOS's usbmuxd service carries a connection over the cable to
//  this device, where it arrives on the loopback interface. So the listener only accepts loopback
//  connections, and nothing on Wi-Fi can reach it. One computer at a time: the newest wins.
//
//  Wire format: one frame per send() call, integers big-endian.
//      UInt32   payload length in bytes
//      UInt32   sequence number, +1 per send() call (batches dropped while
//               disconnected still use a number, so the receiver sees the gap)
//      Float64  phone's Unix time when send() was called
//      bytes    the payload, exactly as passed to send()

import Foundation
import Network

nonisolated final class MotionStreamer: @unchecked Sendable {

    static let defaultPort: UInt16 = 9000

    /// Status messages for your UI, delivered on the main thread.
    var onStatus: (@MainActor (String) -> Void)?

    private let maxInFlight: Int
    private let queue = DispatchQueue(label: "MotionStreamer")

    // Touched only on `queue`.
    private var port: NWEndpoint.Port?    // nil when stopped
    private var generation = 0            // bumped on listen/stop/retry to cancel stale retries
    private var listener: NWListener?
    private var connection: NWConnection?
    private var seq: UInt32 = 0
    private var inFlight = 0

    /// - Parameter maxInFlight: batches allowed to wait on a slow connection before new ones are
    ///   dropped instead of queued, so the stream stays live rather than falling further and
    ///   further behind. The receiver sees drops as a sequence gap. 5 ≈ 0.5 s of 100 ms batches.
    init(maxInFlight: Int = 5) {
        self.maxInFlight = max(1, maxInFlight)
    }

    // MARK: - Listening

    /// Wait for the computer to connect over USB. Keeps listening, so it reconnects when the
    /// computer's app restarts or the cable comes back.
    func listen(port: UInt16 = MotionStreamer.defaultPort) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        queue.async {
            self.generation += 1
            self.port = nwPort
            self.startListener()
        }
    }

    /// Disconnect and stop listening.
    func stop() {
        queue.async {
            self.generation += 1
            self.port = nil
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

        // Not connected, or the connection is backed up: drop this batch rather than build a backlog.
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

    private func startListener() {
        closeAll()
        guard let port else { return }

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true                // send each batch immediately, don't coalesce
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true   // listen again right away after a restart

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            status("Can't listen on port \(port) (\(error)), retrying…")
            scheduleRelisten()
            return
        }
        listener.newConnectionHandler = { [weak self, weak listener] conn in
            guard let self, let listener, listener === self.listener else { conn.cancel(); return }
            self.accept(conn)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else { return }
            switch state {
            case .ready:
                if self.connection == nil { self.status("Waiting for the computer…") }
            case .failed(let error):
                self.status("Stopped listening (\(error)), retrying…")
                self.scheduleRelisten()
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        dropConnection()
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.connection else { return }
            switch state {
            case .ready:
                self.status("Streaming to the computer")
                self.watchForClose(conn)
            case .waiting, .failed:
                self.connectionEnded()
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
                self.connectionEnded()
            } else {
                self.watchForClose(conn)
            }
        }
    }

    /// The listener keeps running, so the computer can connect again.
    private func connectionEnded() {
        dropConnection()
        status("Computer disconnected, waiting for it…")
    }

    private func scheduleRelisten() {
        closeAll()
        generation += 1
        let gen = generation
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.startListener()
        }
    }

    private func dropConnection() {
        connection?.cancel(); connection = nil
        inFlight = 0
    }

    private func closeAll() {
        listener?.cancel(); listener = nil
        dropConnection()
    }

    private func status(_ message: String) {
        Task { @MainActor in self.onStatus?(message) }
    }
}
