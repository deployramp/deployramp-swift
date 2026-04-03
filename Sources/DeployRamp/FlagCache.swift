import Foundation

private let batchIntervalSeconds: TimeInterval = 5.0
private let batchMaxSize = 20

/// Thread-safe cache for feature flags with WebSocket support for real-time updates
/// and batched evaluation event sending.
final class FlagCache: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [String: FlagData] = [:]
    private var wsTask: URLSessionWebSocketTask?
    private var wsURL: URL?
    private var reconnectDelay: TimeInterval = 1.0
    private var closed = false
    private var evalBatch: [EvaluationEvent] = []
    private var batchTimer: DispatchSourceTimer?
    private var perfBatch: [PerformanceEvent] = []
    private var perfBatchTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.deployramp.flagcache", qos: .utility)
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Flag Storage

    /// Replaces all cached flags with the given array.
    func setFlags(_ newFlags: [FlagData]) {
        lock.lock()
        defer { lock.unlock() }
        flags.removeAll()
        for flag in newFlags {
            flags[flag.name] = flag
        }
    }

    /// Returns the cached flag with the given name, or nil.
    func getFlag(_ name: String) -> FlagData? {
        lock.lock()
        defer { lock.unlock() }
        return flags[name]
    }

    // MARK: - Evaluation Batching

    /// Queues an evaluation event. Flushes when the batch reaches max size or after the batch interval.
    func queueEvaluation(_ event: EvaluationEvent) {
        lock.lock()
        evalBatch.append(event)
        let count = evalBatch.count
        let timerActive = batchTimer != nil
        lock.unlock()

        if count >= batchMaxSize {
            flushEvaluations()
        } else if !timerActive {
            startBatchTimer()
        }
    }

    private func startBatchTimer() {
        lock.lock()
        guard batchTimer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + batchIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.flushEvaluations()
        }
        batchTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func flushEvaluations() {
        lock.lock()
        if let timer = batchTimer {
            timer.cancel()
            batchTimer = nil
        }
        guard !evalBatch.isEmpty else {
            lock.unlock()
            return
        }
        let batch = evalBatch
        evalBatch = []
        lock.unlock()

        let message = WsMessage(type: "evaluation_batch", evaluations: batch)
        sendMessage(message)
    }

    // MARK: - Performance Batching

    /// Queues a performance event. Flushes when the batch reaches max size or after the batch interval.
    func queuePerformance(_ event: PerformanceEvent) {
        lock.lock()
        perfBatch.append(event)
        let count = perfBatch.count
        let timerActive = perfBatchTimer != nil
        lock.unlock()

        if count >= batchMaxSize {
            flushPerformance()
        } else if !timerActive {
            startPerfBatchTimer()
        }
    }

    private func startPerfBatchTimer() {
        lock.lock()
        guard perfBatchTimer == nil else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + batchIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.flushPerformance()
        }
        perfBatchTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func flushPerformance() {
        lock.lock()
        if let timer = perfBatchTimer {
            timer.cancel()
            perfBatchTimer = nil
        }
        guard !perfBatch.isEmpty else {
            lock.unlock()
            return
        }
        let batch = perfBatch
        perfBatch = []
        lock.unlock()

        let message = WsMessage(type: "performance_batch", performanceEvents: batch)
        sendMessage(message)
    }

    private func sendMessage(_ message: WsMessage) {
        lock.lock()
        guard let ws = wsTask else {
            lock.unlock()
            return
        }
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(message)
            guard let text = String(data: data, encoding: .utf8) else { return }
            ws.send(.string(text)) { error in
                if error != nil {
                    // Silently ignore send errors
                }
            }
        } catch {
            // Silently ignore encoding errors
        }
    }

    // MARK: - WebSocket

    /// Connects to the WebSocket for real-time flag updates.
    func connectWebSocket(url: URL) {
        lock.lock()
        wsURL = url
        closed = false
        lock.unlock()
        openConnection()
    }

    private func openConnection() {
        lock.lock()
        guard !closed, let url = wsURL else {
            lock.unlock()
            return
        }
        lock.unlock()

        let task = session.webSocketTask(with: url)
        lock.lock()
        wsTask = task
        lock.unlock()

        task.resume()
        receiveMessage(task: task)

        // Reset reconnect delay on successful open
        lock.lock()
        reconnectDelay = 1.0
        lock.unlock()
    }

    private func receiveMessage(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self.receiveMessage(task: task)

            case .failure:
                // Connection lost, schedule reconnect
                self.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let msg = try JSONDecoder().decode(WsMessage.self, from: data)
            if msg.type == "flag_updated" || msg.type == "flags_refreshed" {
                if let newFlags = msg.flags {
                    setFlags(newFlags)
                }
            }
        } catch {
            // Ignore malformed messages
        }
    }

    private func scheduleReconnect() {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30.0)
        lock.unlock()

        let workItem = DispatchWorkItem { [weak self] in
            self?.openConnection()
        }
        lock.lock()
        reconnectWorkItem = workItem
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - Lifecycle

    /// Flushes pending evaluations and tears down WebSocket and timers.
    func close() {
        lock.lock()
        closed = true
        lock.unlock()

        flushEvaluations()
        flushPerformance()

        lock.lock()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        if let timer = batchTimer {
            timer.cancel()
            batchTimer = nil
        }
        if let timer = perfBatchTimer {
            timer.cancel()
            perfBatchTimer = nil
        }

        let ws = wsTask
        wsTask = nil
        flags.removeAll()
        lock.unlock()

        ws?.cancel(with: .goingAway, reason: nil)
    }
}
