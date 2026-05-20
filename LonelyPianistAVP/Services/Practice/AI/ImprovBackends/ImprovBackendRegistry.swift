import Foundation

struct ImprovBackendRegistry: Sendable {
    private var backendsByKind: [ImprovBackendKind: any ImprovBackendProtocol] = [:]

    init(backends: [any ImprovBackendProtocol] = []) {
        for backend in backends {
            backendsByKind[backend.kind] = backend
        }
    }

    mutating func register(_ backend: any ImprovBackendProtocol) {
        backendsByKind[backend.kind] = backend
    }

    func backend(for kind: ImprovBackendKind) -> (any ImprovBackendProtocol)? {
        backendsByKind[kind]
    }
}

