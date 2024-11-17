// The Swift Programming Language
// https://docs.swift.org/swift-book


import Foundation


class APIClient: @unchecked Sendable {
    
    private init() {}
    
    @MainActor static let shared = APIClient()
    
    func fetch<T: Decodable>(
        base_url: String,
        method: String = "GET",
        parameters: [String : Any]? = nil,
        headers: [String : String]? = nil,
        body: Data? = nil,
        timeout: TimeInterval = 60.0,
        token: String? = nil,
        print_response: Bool = false,
        print_status_code: Bool = false,
        completion: @Sendable @escaping (Result<T, Error>) -> Void
    ) {
        
        
        // Build URL Component
        guard var url_components = URLComponents(string: base_url) else {
            completion(.failure(APIError.invalid_url))
            return
        }
        
        
        // Append query parameters for method of type GET
        if method.uppercased() == "GET", let parameters = parameters {
            url_components.queryItems = parameters.map { key, value in
                URLQueryItem(name: key, value: "\(value)")
            }
        }
        
        guard let url = url_components.url else {
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
                switch httpResponse.statusCode {
                    case 100...199:
                        self.print_response(data)
                        self.update_metrics(success: false)
                        completion(.failure(APIError.informational_response))
                        return
                    case 200...299:
                        break
                    case 300...399:
                        self.update_metrics(success: false)
                        completion(.failure(APIError.redirection_response))
                        return
                    case 400...499:
                        self.update_metrics(success: false)
                        completion(.failure(APIError.client_error))
                        return
                    default:
                        self.update_metrics(success: false)
                        completion(.failure(APIError.server_error))
                        return
                }
            }
            
            do {
                let decoded_data = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded_data))
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
    
    private let metrics_queue = DispatchQueue(label: "APIClient.Metrics", attributes: .concurrent)
    private var total_requests: Int = 0
    private var successful_requests: Int = 0
    private var failed_requests: Int = 0
    private var request_timestamps: [Date] = []
    
    public var total_request_count: Int {
        metrics_queue.sync { total_requests }
    }
    
    public var successfully_requested_count: Int {
        metrics_queue.sync { successful_requests }
    }
    
    public var failed_requested_count: Int {
        metrics_queue.sync { failed_requests }
    }
    
    public var requests_per_minute: Double {
        metrics_queue.sync {
            let previous_minute = Date().addingTimeInterval(-60)
            let recent_requests = request_timestamps.filter { $0 > previous_minute}
            return Double(recent_requests.count) / 1.0
        }
    }
    
    public var success_rate: Double {
        metrics_queue.sync {
            total_requests == 0 ? 0 : (Double(successful_requests) / Double(total_requests)) * 100
        }
    }
    
    private func update_metrics(request_started: Bool = false, success: Bool? = nil) {
        metrics_queue.async(flags: .barrier) {
            
            if request_started {
                self.total_requests += 1
                self.request_timestamps.append(Date())
            }
            if let success = success {
                if success {
                    self.successful_requests += 1
                } else {
                    self.failed_requests += 1
                }
            }
        }
    }
    
    private func print_response(_ JSON_data: Data) {
        if let JSON_object = try? JSONSerialization.jsonObject(with: JSON_data, options: []),
        let pretty_data = try? JSONSerialization.data(withJSONObject: JSON_object, options: .prettyPrinted),
        let pretty_string = String(data: pretty_data, encoding: .utf8) {
            print(pretty_string)
        }
    }
}



