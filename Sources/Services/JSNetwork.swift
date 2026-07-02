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
            var resolvedUrlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            let patterns = ["https://", "http://"]
            var lastIndex: String.Index? = nil
            
            for pattern in patterns {
                var searchRange = resolvedUrlString.startIndex..<resolvedUrlString.endIndex
                while let range = resolvedUrlString.range(of: pattern, options: .backwards, range: searchRange) {
                    if lastIndex == nil || range.lowerBound > lastIndex! {
                        lastIndex = range.lowerBound
                    }
                    searchRange = resolvedUrlString.startIndex..<range.lowerBound
                }
            }
            
            if let idx = lastIndex, idx != resolvedUrlString.startIndex {
                resolvedUrlString = String(resolvedUrlString[idx...])
            }
            
            guard let url = URL(string: resolvedUrlString) else {
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
                var textValue = ""
                if let utf8Str = String(data: responseData, encoding: .utf8) {
                    textValue = utf8Str
                } else {
                    let gbkRawValue = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                    let gbkEncoding = String.Encoding(rawValue: gbkRawValue)
                    if let gbkStr = String(data: responseData, encoding: gbkEncoding) {
                        textValue = gbkStr
                    } else if let winStr = String(data: responseData, encoding: .windowsCP1252) {
                        textValue = winStr
                    } else if let asciiStr = String(data: responseData, encoding: .ascii) {
                        textValue = asciiStr
                    }
                }
                
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
