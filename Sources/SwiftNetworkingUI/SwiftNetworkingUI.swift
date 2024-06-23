import SwiftUI
import Foundation
import Combine

// MARK: - URL Session APIs
extension URLSession {
    /// Downloads the contents of a URL, decodes the data, and returns it asynchronously.
    ///
    /// - parameter url: The URL to download data from.
    /// - parameter responseType: The `Codable` type to decode response data to.
    /// - parameter decoder: If necessary, provide a custom JSON decoder here.
    public func data<T>(for url: URL, responseType: T.Type = T.self, decoder: JSONDecoder = .init()) async throws -> T where T: Decodable {
        return try await data(for: .init(url: url), responseType: responseType, decoder: decoder)
    }
    
    /// Downloads the contents of a URL based on the specified URL request, decodes the data, and returns it asynchronously.
    ///
    /// - parameter request: The request to process.
    /// - parameter responseType: The `Codable` type to decode response data to.
    /// - parameter decoder: If necessary, provide a custom JSON decoder here.
    public func data<T>(for request: URLRequest, responseType: T.Type = T.self, decoder: JSONDecoder = .init()) async throws -> T where T: Decodable {
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPError.assertHTTPStatus(response)
        let decodedData = try decoder.decode(T.self, from: data)
        return decodedData
    }
    
    /// Downloads the contents of a URL based on the specified endpoint, decodes the data, and returns it asynchronously.
    ///
    /// - parameter endpoint: The endpoint to query data from.
    /// - parameter obj: Object to encode into the request's body (to use in cases like POST or PUT requests)
    /// - parameter endpointData: Any additional necessary object specifically requested by the provided endpoint.
    /// - parameter decoder: If necessary, provide a custom JSON decoder here.
    public func data<K, R>(for endpoint: Endpoint<K, R>, encoding obj: K.RequestObject? = nil, using endpointData: K.RequestData, decoder: JSONDecoder = .init()) async throws -> R {
        let request = try endpoint.makeRequest(encoding: obj, with: endpointData)
        return try await data(for: request, responseType: R.self, decoder: decoder)
    }
    
    /// Downloads content of a URL based on the specified endpoint and decodes it into a string.
    ///
    /// - parameter endpoint: The endpoint to query data from.
    /// - parameter obj: Object to encode into the request's body (to use in cases like POST or PUT requests)
    /// - parameter endpointData: Any additional necessary object specifically requested by the provided endpoint.
    public func string<K>(for endpoint: Endpoint<K, String>, encoding obj: K.RequestObject? = nil, using endpointData: K.RequestData) async throws -> String {
        let request = try endpoint.makeRequest(encoding: obj, with: endpointData)
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPError.assertHTTPStatus(response)
        let result = String(decoding: data, as: UTF8.self)
        return result
    }
    
    /// Querys a URL based on the specified endpoint and ignores the returned data.
    ///
    /// - parameter endpoint: The endpoint to query data from.
    /// - parameter obj: Object to encode into the request's body (to use in cases like POST or PUT requests)
    /// - parameter endpointData: Any additional necessary object specifically requested by the provided endpoint.
    public func query<K>(endpoint: Endpoint<K, StubCodable>, encoding obj: K.RequestObject? = nil, using endpointData: K.RequestData) async throws {
        let request = try endpoint.makeRequest(encoding: obj, with: endpointData)
        let (_, response) = try await URLSession.shared.data(for: request)
        try HTTPError.assertHTTPStatus(response)
    }
}

// MARK: - Authentication Types
public struct BasicAccessToken {
    var username: String
    var password: String
    
    init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

// MARK: - Endpoint APIs
public protocol EndpointKind {
    /// Any additional piece of data of any type (including tuples) which can be used as additional parameters to configure a particular endpoint. Can pass `Void` to ignore this field.
    ///
    /// An example usage would be to pass any authentication parameters for automatic configuration. This is what the built-in endpoint kinds do.
    associatedtype RequestData
    /// The struct to be encoded into the request body. Can pass `StubCodable` to ignore this field.
    ///
    /// As of this version, the data can only be encoded as JSON, for other format, use the `customRequestConfigurator` on the `Endpoint` class.
    associatedtype RequestObject: Encodable
    
    /// Prepare the URL request by encoding the provided object and passing the additional data.
    static func prepare(_ request: inout URLRequest, encoding obj: RequestObject?, with data: RequestData) throws
}

public enum EndpointKinds {
    /// Public endpoint without any access control
    public enum Public: EndpointKind {
        public static func prepare(_ request: inout URLRequest, encoding _: StubCodable?, with _: Void) {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
    }
    
    /// Endpoints that takes basic authentications
    enum BasicAuthenticable: EndpointKind {
        static func prepare(_ request: inout URLRequest, encoding _: StubCodable? = nil, with token: BasicAccessToken) {
            let loginString = "\(token.username):\(token.password)"
            let loginData = Data(loginString.utf8)
            let base64LoginString = loginData.base64EncodedString()
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        }
    }
    
    /// Endpoints that takes basic authentications (see `BasicAuthenticable`)
    typealias BasicGet = BasicAuthenticable
    
    /// Endpoints that takes bearer authentications
    enum BearerAuthenticable: EndpointKind {
        static func prepare(_ request: inout URLRequest, encoding _: StubCodable? = nil, with token: String) {
            let bearerToken = "Bearer \(token)"
            request.setValue(bearerToken, forHTTPHeaderField: "Authorization")
        }
    }
    
    /// Endpoints that takes bearer authentications (see `BearerAuthenticable`)
    typealias BearerGet = BearerAuthenticable
    
    /// Endpoint kind for uploading data, uses bearer authentication
    enum Upload<Type: Encodable>: EndpointKind {
        static func prepare(_ request: inout URLRequest, encoding obj: Type?, with token: String) throws {
            // First prepare using bearer authenticator
            BearerAuthenticable.prepare(&request, with: token)
            
            if let obj = obj {
                try JSONEncodeHelper.encode(object: obj, to: &request)
            }
            
            request.httpMethod = "POST"
        }
    }
    
    enum Edit<Type: Encodable>: EndpointKind {
        static func prepare(_ request: inout URLRequest, encoding obj: Type?, with token: String) throws {
            // Prepare with the upload kind
            try Upload<Type>.prepare(&request, encoding: obj, with: token)
            
            request.httpMethod = "PUT"
        }
    }
    
    enum Delete<Type: Encodable>: EndpointKind {
        static func prepare(_ request: inout URLRequest, encoding obj: Type?, with token: String) throws {
            // Prepare with the upload kind
            try Upload<Type>.prepare(&request, encoding: obj, with: token)
            
            request.httpMethod = "DELETE"
        }
    }
}

private enum JSONEncodeHelper {
    static func encode<O: Encodable>(object: O, to request: inout URLRequest) throws {
        // TODO: Support custom encoders (not required right now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(object)
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\(encodedData.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = encodedData
    }
}

/// Stub struct for when `Request` generic is not required
public struct StubCodable: Codable {}

/// Use to specify an endpoint for querying data from server.
public struct Endpoint<Kind: EndpointKind, Response: Decodable> {
    /// Path to endpoint
    public var url: URL
    /// Optional custom configurations to the request
    public var customRequestConfigurator: ((URLRequest) -> URLRequest)?
    
    public init(url: URL, customRequestConfigurator: ( (URLRequest) -> URLRequest)? = nil) {
        self.url = url
        self.customRequestConfigurator = customRequestConfigurator
    }
}

public extension Endpoint {
    /// Create an `URLRequest` for this endpoint
    func makeRequest(encoding obj: Kind.RequestObject?, with requestData: Kind.RequestData) throws -> URLRequest {
        var request = URLRequest(url: self.url)
        try Kind.prepare(&request, encoding: obj, with: requestData)
        if let customRequestConfigurator {
            request = customRequestConfigurator(request)
        }
        return request
    }
}

// MARK: - Data Uploader
/// Conform to this protocol to automatically support uploading the object to an specified endpoint.
protocol DataUploader: Codable {
    associatedtype Kind: EndpointKind
    associatedtype Response: Decodable
    
    var targetURL: URL { get }
    var jsonDecoder: JSONDecoder { get }
}

extension DataUploader {
    // Default Implementation for JSON Decoder, without any special options
    var jsonDecoder: JSONDecoder {
        JSONDecoder()
    }
}

//extension DataUploader where Kind.RequestData == String, Kind.RequestObject == Self {
//    /// When the required endpoint for this data uploader supports bearer authentication, use this method to automatically create a publisher for the data uploader.
//    func createPublisher(with credential: LoginCredential) -> AnyPublisher<Response, Error> {
//        let url = urlForUploader(from: credential.server)
//        let endpoint = Endpoint<Kind, Response>(url: url)
//        return URLSession.shared.publisher(for: endpoint, encoding: self, using: credential.user.token, decoder: iso8601JSONDecoder)
//    }
//}
//
//extension DataUploader where Kind.RequestData == String, Kind.RequestObject == StubCodable {
//    /// When the required endpoint for this data uploader supports bearer authentication, use this method to automatically create a publisher for the data uploader.
//    func createPublisher(with credential: LoginCredential) -> AnyPublisher<Response, Error> {
//        let url = urlForUploader(from: credential.server)
//        let endpoint = Endpoint<Kind, Response>(url: url)
//        return URLSession.shared.publisher(for: endpoint, encoding: nil, using: credential.user.token, decoder: iso8601JSONDecoder)
//    }
//}
//
//extension DataUploader where Kind.RequestData == String, Kind.RequestObject == Self, Response == StubCodable {
//    /// When the required endpoint for this data uploader supports bearer authentication, use this method to automatically create a publisher for the data uploader. This method is used because there are no result from the query, therefore will not decode the result.
//    func createPublisher(with credential: LoginCredential) -> AnyPublisher<Void, Error> {
//        let url = urlForUploader(from: credential.server)
//        let endpoint = Endpoint<Kind, Response>(url: url)
//        return URLSession.shared.publisher(forRequestOnlyEndpoint: endpoint, encoding: self, using: credential.user.token)
//    }
//}
//
//extension DataUploader where Kind.RequestData == String, Kind.RequestObject == StubCodable, Response == StubCodable {
//    /// When the required endpoint for this data uploader supports bearer authentication, use this method to automatically create a publisher for the data uploader. This method is used because there are no result from the query, therefore will not decode the result.
//    func createPublisher(with credential: LoginCredential) -> AnyPublisher<Void, Error> {
//        let url = urlForUploader(from: credential.server)
//        let endpoint = Endpoint<Kind, Response>(url: url)
//        return URLSession.shared.publisher(forRequestOnlyEndpoint: endpoint, encoding: nil, using: credential.user.token)
//    }
//}

// MARK: - URL Builder
/// Allows different types to be passed into `URL.build`
protocol URLPathAllowed {
    /// Convert the instance to a path component of URL
    var pathRepresentation: String { get }
}

extension String: URLPathAllowed {
    var pathRepresentation: String { self }
}

extension UUID: URLPathAllowed {
    var pathRepresentation: String { self.uuidString }
}

extension URL {
    /// Build URL using variadic parameters
    static func build(from base: URL, _ pathComponents: URLPathAllowed...) -> URL {
        var result = base
        for component in pathComponents {
            result = result.appendingPathComponent(component.pathRepresentation)
        }
        return result
    }
}
