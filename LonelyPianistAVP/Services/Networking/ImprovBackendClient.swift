import Foundation

enum ImprovBackendClientError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodeFailed
}

protocol ImprovBackendClientProtocol {
    func generate(
        host: String,
        port: Int,
        request: ImprovGenerateRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> ImprovResultResponse
}

struct ImprovBackendClient: ImprovBackendClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func generate(
        host: String,
        port: Int,
        request: ImprovGenerateRequest,
        timeoutSeconds: TimeInterval = 2
    ) async throws -> ImprovResultResponse {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/generate"

        guard let url = components.url else {
            throw ImprovBackendClientError.invalidURL
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImprovBackendClientError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let message = (try? decoder.decode(ImprovErrorResponse.self, from: data))?.message
            throw ImprovBackendClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        if let result = try? decoder.decode(ImprovResultResponse.self, from: data) {
            return result
        }
        if let error = try? decoder.decode(ImprovErrorResponse.self, from: data) {
            throw ImprovBackendClientError.httpError(statusCode: httpResponse.statusCode, message: error.message)
        }
        throw ImprovBackendClientError.decodeFailed
    }
}

