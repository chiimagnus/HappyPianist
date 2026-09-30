import Foundation

enum ImprovBackendClientError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, code: String, message: String?)
    case decodeFailed
}

protocol ImprovBackendClientProtocol: Sendable {
    func generate(
        host: String,
        port: Int,
        request: AriaGenerateRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> AriaResultResponse
}

struct ImprovBackendClient: ImprovBackendClientProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func generate(
        host: String,
        port: Int,
        request: AriaGenerateRequest,
        timeoutSeconds: TimeInterval
    ) async throws -> AriaResultResponse {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = AriaNetworkProtocol.path

        guard let url = components.url else {
            throw ImprovBackendClientError.invalidURL
        }
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw URLError(.timedOut)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImprovBackendClientError.invalidResponse
        }

        let decoder = JSONDecoder()
        if httpResponse.statusCode != 200 {
            do {
                let error = try decoder.decode(AriaErrorResponse.self, from: data)
                throw ImprovBackendClientError.httpError(
                    statusCode: httpResponse.statusCode,
                    code: error.code,
                    message: error.message
                )
            } catch let error as ImprovBackendClientError {
                throw error
            } catch {
                throw ImprovBackendClientError.decodeFailed
            }
        }

        do {
            return try decoder.decode(AriaResultResponse.self, from: data)
        } catch {
            throw ImprovBackendClientError.decodeFailed
        }
    }
}
