// The Swift Programming Language
// https://docs.swift.org/swift-book


import Foundation


public class APIClient: @unchecked Sendable {
    
    public init() {}
    
    @MainActor static let shared = APIClient()
    
    public func fetch<T: Decodable>(
        baseUrl: String,
        method: String = "GET",
        parameters: [String : Any]? = nil,
        headers: [String : String]? = nil,
        body: Data? = nil,
        timeout: TimeInterval = 60.0,
        token: String? = nil,
        printResponse: Bool = false,
        completion: @Sendable @escaping (Result<T, Error>) -> Void
    ) {
        
        
        // Build URL Component
        guard var urlComponents = URLComponents(string: baseUrl) else {
            completion(.failure(APIError.invalid_url))
            return
        }
        
        
        // Append query parameters for method of type GET
        if method.uppercased() == "GET", let parameters = parameters {
            urlComponents.queryItems = parameters.map { key, value in
                URLQueryItem(name: key, value: "\(value)")
            }
        }
        
        guard let url = urlComponents.url else {
            completion(.failure(APIError.invalid_url))
            return
        }
        
        
        // Construct request
        var request  = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        
        // headers
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }
        
        // bearer token
        if let token = token {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // handle paramters for non-GET requests
        if method.uppercased() != "GET" {
            if let body = body {
                request.httpBody = body
            } else if let parameters = parameters {
                request.httpBody = try? JSONSerialization.data(withJSONObject: parameters, options: [])
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        
        
        // perform request
        let session = URLSession.shared
        let task = session.dataTask(with: request) { data, response, error in
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(APIError.nil_data))
                return
            }
            
            // check status codes
            if let httpResponse = response as? HTTPURLResponse {
                if printResponse { print("Status:", httpResponse.statusCode) }
                switch httpResponse.statusCode {
                    case 100...199:
                        completion(.failure(APIError.informational_response))
                        return
                    case 200...299:
                        break
                    case 300...399:
                        completion(.failure(APIError.redirection_response))
                        return
                    case 400...499:
                        completion(.failure(APIError.client_error))
                        return
                    default:
                        completion(.failure(APIError.server_error))
                        return
                }
            }
            
            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                if printResponse { self.printJSON(data) }
                completion(.success(decodedData))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    public enum APIError: Error {
        case invalid_url
        case nil_data
        case decoding_error
        
        case informational_response
        case redirection_response
        case client_error
        case server_error
    }
    
    private func printJSON(_ JSON_data: Data) {
        if let JSON_object = try? JSONSerialization.jsonObject(with: JSON_data, options: []),
        let pretty_data = try? JSONSerialization.data(withJSONObject: JSON_object, options: .prettyPrinted),
        let pretty_string = String(data: pretty_data, encoding: .utf8) {
            print(pretty_string)
        }
    }
}



