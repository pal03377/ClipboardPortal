import Foundation

enum ServerRequestError: Int, Error {
    case networkError = 0
    case badRequest = 400
    case forbidden = 403
    case notFound = 404
    case payloadTooLarge = 413
    case serverError = 500
    case serverDown = 502
    case unknown = -1
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
        case .payloadTooLarge:
            return "Too much data."
        case .serverError:
            return "A server error occurred. Please try again later."
        case .serverDown:
            return "The server is offline. Please try again later."
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

struct ServerRequest {
    // Configure these values by editing ConfigDevelopment.xcconfig and ConfigProduction.xcconfig

    // Send a POST request to the server
    static func post<T: Decodable>(url: URL, body: Encodable) async throws -> T { // Send POST data to server
        print("url \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type") // Send JSON header to server
        request.addValue("application/json", forHTTPHeaderField: "Accept") // Request JSON answer from server
        request.httpBody = try JSONEncoder().encode(body) // Encode request body
        return try await sendRequest(request)
    }
    // Send a GET request to the server
    static func get<T: Decodable>(url: URL) async throws -> T { // Send GET request to server
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
        guard let response = response as? HTTPURLResponse else { throw ServerRequestError.unknown }
        guard (200...299).contains(response.statusCode) else {
            // Throw if server responded with non-ok status code
            throw ServerRequestError(rawValue: response.statusCode) ?? .unknown
        }
        if T.self == String.self { // String wanted?
            if let stringValue = String(data: responseData, encoding: .utf8) { // Decode as string
                return stringValue as! T
            } else { // Decode error?
                throw ServerRequestError.unknown // Throw
            }
        } else { // Some other data structure?
            return try JSONDecoder().decode(T.self, from: responseData) // Decode with JSON
        }
    }
}
