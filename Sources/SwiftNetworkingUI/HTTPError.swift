import Foundation

enum HTTPError: LocalizedError {
    case preprocess
    case invalidResponse
    case permissionDenied
    case invalidLogin
    case invalidData
    case statusCode(code: Int)
    case other(error: Error)
    
    var errorDescription: String? {
        return getErrorString()
    }
    
    private func getErrorString() -> String {
        switch self {
        case .preprocess:
            return "Cannot prepare request for server!"
        case .permissionDenied:
            return "Permission Denied! Please restart the app."
        case .invalidLogin:
            return "Invalid login credential!"
        case .invalidResponse:
            return "The server returned an invalid response."
        case .statusCode(let code):
            return "The server returned an invalid status code (\(code))."
        case .invalidData:
            return "The server returned unreadable data."
        case .other(let error):
            return error.localizedDescription
        }
    }
    
    /// Standard check for server errors (throws if error, returns if success)
    static func assertHTTPStatus(_ response: URLResponse, login: Bool = false) throws {
        guard let response = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }
        
        guard response.statusCode != 401 && response.statusCode != 403 else {
            // Permission denied from server
            if login {
                throw HTTPError.invalidLogin
            } else {
                throw HTTPError.permissionDenied
            }
        }
        
        // Allow all 2xx Success codes to pass through
        guard response.statusCode >= 200 && response.statusCode <= 299 else {
            throw HTTPError.statusCode(code: response.statusCode)
        }
    }
}

