import Foundation
import JavaScriptCore

@objc protocol JSResponseDataExport: JSExport {
    var textValue: String { get }
    var status: Int { get }
    var headers: [String: String] { get }
}

@objc public final class JSResponseData: NSObject, JSResponseDataExport {
    public var textValue: String
    public var status: Int
    public var headers: [String: String]
    
    public init(textValue: String, status: Int, headers: [String: String]) {
        self.textValue = textValue
        self.status = status
        self.headers = headers
    }
}

public final class JSNetwork {
    public static func registerFetch(in context: JSContext) {
        // 1. Định nghĩa hàm _nativeFetch trong Swift
        let nativeFetchBlock: @convention(block) (String, NSDictionary, JSValue) -> Void = { urlString, options, callback in
            guard let url = URL(string: urlString) else {
                callback.call(withArguments: ["Invalid URL: \(urlString)", NSNull()])
                return
            }
            
            var request = URLRequest(url: url)
            
            // Set method
            if let method = options["method"] as? String {
                request.httpMethod = method.uppercased()
            } else {
                request.httpMethod = "GET"
            }
            
            // Set headers
            if let headers = options["headers"] as? [String: String] {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            
            // Set body
            if let bodyString = options["body"] as? String {
                request.httpBody = bodyString.data(using: .utf8)
            }
            
            // Cấu hình Session với timeout hợp lý
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config)
            
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    callback.call(withArguments: [error.localizedDescription, NSNull()])
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    callback.call(withArguments: ["Invalid HTTP Response", NSNull()])
                    return
                }
                
                let responseData = data ?? Data()
                // Thử decode utf8, nếu lỗi dùng ascii làm phương án dự phòng
                let textValue = String(data: responseData, encoding: .utf8) ?? String(data: responseData, encoding: .ascii) ?? ""
                
                var headersDict: [String: String] = [:]
                for (key, value) in httpResponse.allHeaderFields {
                    if let keyStr = key as? String, let valStr = value as? String {
                        headersDict[keyStr] = valStr
                    }
                }
                
                let jsResponse = JSResponseData(textValue: textValue, status: httpResponse.statusCode, headers: headersDict)
                callback.call(withArguments: [NSNull(), jsResponse])
            }
            
            task.resume()
        }
        
        // Đăng ký _nativeFetch vào JSContext
        context.setObject(nativeFetchBlock, forKeyedSubscript: "_nativeFetch" as NSCopying & NSObjectProtocol)
        
        // 2. Viết mã Javascript bootstrap để định nghĩa hàm fetch() toàn cục dạng Promise
        let fetchBootstrap = """
        function fetch(url, options) {
            return new Promise(function(resolve, reject) {
                _nativeFetch(url, options || {}, function(error, response) {
                    if (error) {
                        reject(new Error(error));
                    } else {
                        resolve({
                            text: function() { return Promise.resolve(response.textValue); },
                            json: function() { return Promise.resolve(JSON.parse(response.textValue)); },
                            html: function() { return Html.parse(response.textValue); },
                            status: response.status,
                            headers: response.headers
                        });
                    }
                });
            });
        }
        """
        
        context.evaluateScript(fetchBootstrap)
    }
}
