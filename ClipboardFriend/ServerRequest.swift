import Foundation

enum ServerRequestError: Error {
    case networkError
    case badRequest
    case forbidden
    case notFound
    case serverError
    case unknown(Int)
}
extension ServerRequestError: LocalizedError { // Nice error messages
    public var errorDescription: String? {
        switch self {
        case .networkError:
            return "A network error occurred. Please check your connection and try again."
        case .badRequest:
            return "Bad request. Please check the request and try again."
        case .forbidden:
            return "Forbidden. You don't have permission to access this resource."
        case .notFound:
            return "Resource not found. Please check the URL and try again."
        case .serverError:
            return "A server error occurred. Please try again later."
        case .unknown(let code):
            return "An unknown error occurred. (Error code: \(code))"
        }
    }
}

struct ServerRequest {
    // Configure these values by editing ConfigDevelopment.xcconfig and ConfigProduction.xcconfig
    static var serverUrl: URL {
        let serverUrlString = Bundle.main.object(forInfoDictionaryKey: "ServerURL") as? String
        return URL(string: serverUrlString!)!
    }

    // Send a POST request to the server
    static func post<T: Decodable>(path: String, body: Encodable) async throws -> T { // Send POST data to server at e.g. "/path"
        let url = serverUrl.appendingPathComponent(path) // Create URL from path e.g. "/path" -> URL("https://example.com/path")
        print("url \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type") // Send JSON header to server
        request.addValue("application/json", forHTTPHeaderField: "Accept") // Request JSON answer from server
        request.httpBody = try JSONEncoder().encode(body) // Encode request body
        return try await sendRequest(request)
    }
    // Send a PUT request to the server
    static func put<T: Decodable>(path: String, body: Encodable) async throws -> T { // Send PUT data to server at e.g. "/path"
        let url = serverUrl.appendingPathComponent(path) // Create URL from path e.g. "/path" -> URL("https://example.com/path")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type") // Send JSON header to server
        request.addValue("application/json", forHTTPHeaderField: "Accept") // Request JSON answer from server
        request.httpBody = try JSONEncoder().encode(body) // Encode request body
        return try await sendRequest(request)
    }
    // Send a GET request to the server
    static func get<T: Decodable>(path: String) async throws -> T { // Send GET request to server at e.g. "/path"
        let url = serverUrl.appendingPathComponent(path) // Create URL from path e.g. "/path" -> URL("https://example.com/path")
        let request = URLRequest(url: url)
        return try await sendRequest(request)
    }
    // Helper function to send, check and decode a request
    private static func sendRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        var responseData: Data, response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.data(for: request) // Send request
        } catch {
            print(error)
            throw ServerRequestError.networkError
        }
        guard let response = response as? HTTPURLResponse else { throw ServerRequestError.unknown(-1) }
        guard (200...299).contains(response.statusCode) else {
            // Throw if server responded with non-ok status code
            switch response.statusCode {
            case 400: throw ServerRequestError.badRequest
            case 403: throw ServerRequestError.forbidden
            case 404: throw ServerRequestError.notFound
            case 500: throw ServerRequestError.serverError
            default: throw ServerRequestError.unknown(response.statusCode)
            }
        }
        return try JSONDecoder().decode(T.self, from: responseData) // Decode and return response
    }
}
