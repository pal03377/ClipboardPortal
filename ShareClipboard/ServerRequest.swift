import Foundation

struct ServerRequest {
    // Configure these values by editing ConfigDevelopment.xcconfig and ConfigProduction.xcconfig
    static var serverUrl: URL {
        let serverUrlString = Bundle.main.object(forInfoDictionaryKey: "ServerURL") as? String
        return URL(string: serverUrlString!)!
    }

    // Send a POST request to the server
    static func post<T: Decodable>(path: String, body: Encodable) async throws -> T { // Send POST data to server at e.g. "/path"
        let url = serverUrl.appendingPathComponent(path) // Create URL from path e.g. "/path" -> URL("https://example.com/path")
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
        let (responseData, response) = try await URLSession.shared.data(for: request) // Send request
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) } // Throw if server responded with non-ok status code
        return try JSONDecoder().decode(T.self, from: responseData) // Decode and return response
    }
}
