import Foundation
import Network
import os

@MainActor
final class BonjourBackendDiscoveryService: Sendable {
    static let defaultServiceType: String = "_lpduet._tcp"

    enum State: Equatable {
        case idle
        case discovering
        case resolved(host: String, port: Int, txtRecord: [String: String])
        case failed(message: String)
        case denied
    }

    private let serviceType: String
    private let requiredTXTRecord: [String: String]
    private let resolutionTimeout: Duration
    private(set) var state: State = .idle

    private var browser: NWBrowser?
    private var resolveTask: Task<Void, Never>?

    init(
        serviceType: String = BonjourBackendDiscoveryService.defaultServiceType,
        requiredTXTRecord: [String: String] = [:],
        resolutionTimeout: Duration = .seconds(2)
    ) {
        self.serviceType = serviceType
        self.requiredTXTRecord = requiredTXTRecord
        self.resolutionTimeout = resolutionTimeout
    }

    var resolvedEndpoint: (host: String, port: Int)? {
        if case let .resolved(host, port, _) = state {
            return (host, port)
        }
        return nil
    }

    func start() {
        guard browser == nil else { return }
        state = .discovering

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch newState {
                case let .failed(error):
                    if case let .posix(code) = error, code == .EPERM {
                        state = .denied
                    } else {
                        state = .failed(message: String(describing: error))
                    }
                    stop()
                case .cancelled:
                    if case .discovering = state {
                        state = .idle
                    }
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard resolvedEndpoint == nil else { return }
                guard resolveTask == nil else { return }
                let candidates = selectCandidates(from: results)
                guard candidates.isEmpty == false else { return }
                resolveTask = Task { [weak self] in
                    await self?.resolveAndPublish(candidates: candidates)
                }
            }
        }

        browser.start(queue: .global(qos: .utility))
    }

    func stop() {
        resolveTask?.cancel()
        resolveTask = nil

        browser?.cancel()
        browser = nil
    }

    private func resolveAndPublish(candidates: [NWBrowser.Result]) async {
        defer { resolveTask = nil }

        for result in candidates {
            guard Task.isCancelled == false else { return }

            let endpoint = result.endpoint
            let txtRecord = extractTXTRecordStrings(from: result.metadata) ?? [:]
            let resolved = await resolveHostPort(
                from: endpoint,
                timeout: resolutionTimeout
            )

            guard Task.isCancelled == false else { return }
            if let resolved {
                state = .resolved(
                    host: resolved.host,
                    port: resolved.port,
                    txtRecord: txtRecord
                )
                return
            }
        }
    }

    private func selectCandidates(from results: Set<NWBrowser.Result>) -> [NWBrowser.Result] {
        var candidates = Array(results)
        candidates.sort { lhs, rhs in
            String(describing: lhs.endpoint) < String(describing: rhs.endpoint)
        }

        guard requiredTXTRecord.isEmpty == false else {
            return candidates
        }

        return candidates.filter { matchesRequiredTXTRecord(metadata: $0.metadata) }
    }

    private nonisolated func matchesRequiredTXTRecord(metadata: NWBrowser.Result.Metadata) -> Bool {
        guard let txt = extractTXTRecordStrings(from: metadata) else { return false }

        for (rawKey, rawValue) in requiredTXTRecord {
            let key = rawKey.lowercased()
            let expected = rawValue.lowercased()
            guard let actual = txt[key]?.lowercased() else { return false }
            guard actual == expected else { return false }
        }

        return true
    }

    private nonisolated func extractTXTRecordStrings(from metadata: NWBrowser.Result.Metadata) -> [String: String]? {
        guard case let .bonjour(txtRecord) = metadata else { return nil }
        return parseTXTRecordData(txtRecord.data)
    }

    private nonisolated func parseTXTRecordData(_ data: Data) -> [String: String] {
        // TXT record data is a sequence of length-prefixed strings:
        //   <len><bytes...><len><bytes...>...
        var result: [String: String] = [:]
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let length = Int(bytes[index])
            index += 1
            guard length > 0 else { continue }
            guard index + length <= bytes.count else { break }

            let fieldBytes = bytes[index ..< index + length]
            index += length

            let field = String(decoding: fieldBytes, as: UTF8.self)
            if let equalsIndex = field.firstIndex(of: "=") {
                let key = String(field[..<equalsIndex]).lowercased()
                let value = String(field[field.index(after: equalsIndex)...])
                result[key] = value
            } else {
                result[field.lowercased()] = ""
            }
        }
        return result
    }

    private nonisolated func resolveHostPort(
        from endpoint: NWEndpoint,
        timeout: Duration
    ) async -> (host: String, port: Int)? {
        enum ResolutionEvent: Sendable {
            case resolved(host: String, port: Int)
            case failed
        }

        let connection = NWConnection(to: endpoint, using: .tcp)
        let events = AsyncStream<ResolutionEvent> { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                        continuation.yield(
                            .resolved(
                                host: self.normalizeResolvedHost(String(describing: host)),
                                port: Int(port.rawValue)
                            )
                        )
                    } else {
                        continuation.yield(.failed)
                    }
                    continuation.finish()
                case .failed, .cancelled:
                    continuation.yield(.failed)
                    continuation.finish()
                case .setup, .waiting, .preparing:
                    break
                @unknown default:
                    continuation.yield(.failed)
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                connection.cancel()
            }
            connection.start(queue: .global(qos: .utility))
        }

        defer { connection.cancel() }

        return await withTaskGroup(of: (host: String, port: Int)?.self) { group in
            group.addTask {
                for await event in events {
                    switch event {
                    case let .resolved(host, port):
                        return (host, port)
                    case .failed:
                        return nil
                    }
                }
                return nil
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return nil
                }
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private nonisolated func normalizeResolvedHost(_ host: String) -> String {
        // Some Network framework debug strings can include an interface scope suffix (e.g. "172.20.10.3%ir0").
        // URLSession cannot build a valid URL from such a host. For IPv4-looking hosts, drop the scope suffix.
        guard let percentIndex = host.firstIndex(of: "%") else { return host }
        let prefix = String(host[..<percentIndex])
        if prefix.isEmpty { return host }

        let isIPv4Like = prefix.split(separator: ".", omittingEmptySubsequences: false).count == 4
            && prefix.allSatisfy { $0.isNumber || $0 == "." }
        if isIPv4Like {
            return prefix
        }

        // For non-IPv4 hosts we keep the original string to avoid breaking IPv6 link-local resolution.
        return host
    }
}

@MainActor
protocol BonjourBackendDiscoveryServiceProtocol: AnyObject, Sendable {
    var state: BonjourBackendDiscoveryService.State { get }
    func start()
    func stop()
}

extension BonjourBackendDiscoveryService: BonjourBackendDiscoveryServiceProtocol {}
