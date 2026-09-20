import Foundation

enum CompanionDecisionBackendRegistryError: Error, Equatable {
    case invalidSelection
    case unavailable(CompanionDecisionBackendKind)
    case selectionChanged
}

struct CompanionDecisionBackendRegistry {
    private var backendsByKind: [CompanionDecisionBackendKind: any CompanionDecisionBackendProtocol] = [:]

    init(backends: [any CompanionDecisionBackendProtocol] = []) {
        for backend in backends {
            backendsByKind[backend.kind] = backend
        }
    }

    func backend(
        for kind: CompanionDecisionBackendKind
    ) throws -> any CompanionDecisionBackendProtocol {
        guard let backend = backendsByKind[kind] else {
            throw CompanionDecisionBackendRegistryError.unavailable(kind)
        }
        return backend
    }
}
