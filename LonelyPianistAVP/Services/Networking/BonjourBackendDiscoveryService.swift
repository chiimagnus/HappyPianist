import Foundation
import Network
import Observation
import os

@MainActor
@Observable
final class BonjourBackendDiscoveryService {
    enum State: Equatable {
        case idle
        case discovering
        case resolved(host: String, port: Int)
        case failed(message: String)
        case denied
    }

    private(set) var state: State = .idle

    private var browser: NWBrowser?
    private var resolveTask: Task<Void, Never>?

    var resolvedEndpoint: (host: String, port: Int)? {
        if case let .resolved(host, port) = state {
            return (host, port)
        }
        return nil
    }

    func start() {
        guard browser == nil else { return }
        state = .discovering

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_lonelypianist._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch newState {
                    case .failed(let error):
                        if case let .posix(code) = error, code == .EPERM {
                            self.state = .denied
                        } else {
                            self.state = .failed(message: String(describing: error))
                        }
                        self.stop()
                    case .cancelled:
                        if case .discovering = self.state {
                            self.state = .idle
                        }
                    default:
                        break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _changes in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.resolvedEndpoint == nil else { return }
                guard self.resolveTask == nil else { return }
                guard let result = results.first else { return }
                self.resolveTask = Task { [weak self] in
                    await self?.resolveAndPublish(result: result)
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

    private func resolveAndPublish(result: NWBrowser.Result) async {
        defer {
            Task { @MainActor [weak self] in
                self?.resolveTask = nil
            }
        }

        let endpoint = result.endpoint
        let resolved = await resolveHostPort(from: endpoint)
        await MainActor.run {
            if let resolved {
                self.state = .resolved(host: resolved.host, port: resolved.port)
            } else if case .discovering = self.state {
                // Keep discovering. A transient resolve failure should not permanently lock the service in `.failed`.
            }
        }
    }

    nonisolated private func resolveHostPort(from endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        await withCheckedContinuation(isolation: nil) { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let lock = OSAllocatedUnfairLock(initialState: false)

            @Sendable func finish(_ value: (host: String, port: Int)?) {
                let shouldResume = lock.withLock { alreadyFinished in
                    if alreadyFinished {
                        return false
                    }
                    alreadyFinished = true
                    return true
                }
                guard shouldResume else { return }
                continuation.resume(returning: value)
                connection.cancel()
            }

            connection.stateUpdateHandler = { state in
                switch state {
                    case .ready:
                        if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                            finish((host: String(describing: host), port: Int(port.rawValue)))
                        } else {
                            finish(nil)
                        }
                    case .failed:
                        finish(nil)
                    default:
                        break
                }
            }

            connection.start(queue: .global(qos: .utility))
        }
    }
}
