import Foundation

enum ImprovBackendRegistryError: Error, Equatable {
    case unavailable(ImprovBackendKind)
}

struct ImprovBackendRegistry {
    private var backendsByKind: [ImprovBackendKind: any ImprovBackendProtocol] = [:]

    init(backends: [any ImprovBackendProtocol] = []) {
        for backend in backends {
            backendsByKind[backend.kind] = backend
        }
    }

    func backend(for kind: ImprovBackendKind) throws -> any ImprovBackendProtocol {
        guard let backend = backendsByKind[kind] else {
            throw ImprovBackendRegistryError.unavailable(kind)
        }
        return backend
    }
}
