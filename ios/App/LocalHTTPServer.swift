import Foundation
import Network

/// 轻量本地 HTTP 服务器（无外部依赖）
/// - 提供 App Bundle 中的 web 静态文件
/// - 代理 /api/fish/* 请求到 https://api.fish.audio/*，绕开 CORS
class LocalHTTPServer {

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.voicereader.httpserver", qos: .userInitiated)

    func start() -> UInt {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: 0)
        } catch {
            print("[LocalHTTPServer] 创建 listener 失败: \(error)")
            return 0
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                if let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    print("[LocalHTTPServer] 已启动: http://localhost:\(port)")
                }
            }
        }

        listener?.start(queue: queue)

        // 等待端口分配（最多 2 秒）
        let semaphore = DispatchSemaphore(value: 0)
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if self?.port ?? 0 > 0 {
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + 2)

        return UInt(port)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        print("[LocalHTTPServer] 已停止")
    }

    // MARK: - 连接处理

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection: connection, buffer: Data())
    }

    private func receiveRequest(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[LocalHTTPServer] 接收错误: \(error)")
                connection.cancel()
                return
            }

            var newBuffer = buffer
            if let data = data {
                newBuffer.append(data)
            }

            // 检查是否收到完整的 HTTP 请求头（以 \r\n\r\n 结尾）
            guard let headerEnd = self.findHeaderEnd(in: newBuffer) else {
                if isComplete {
                    connection.cancel()
                    return
                }
                self.receiveRequest(connection: connection, buffer: newBuffer)
                return
            }

            // 解析请求
            let headerData = newBuffer.prefix(upTo: headerEnd + 4)
            let bodyData = newBuffer.suffix(from: headerEnd + 4)

            guard let request = self.parseHTTPRequest(headerData: headerData) else {
                self.sendError(connection: connection, status: 400, message: "Bad Request")
                return
            }

            // 检查是否需要读取更多 body
            let contentLength = request.headers["content-length"].flatMap { Int($0) } ?? 0
            if bodyData.count < contentLength {
                self.receiveRequestBody(connection: connection, request: request, buffer: newBuffer, remaining: contentLength - bodyData.count)
            } else {
                request.body = bodyData.prefix(contentLength)
                self.processRequest(request: request, connection: connection)
            }
        }
    }

    private func receiveRequestBody(connection: NWConnection, request: HTTPRequest, buffer: Data, remaining: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                print("[LocalHTTPServer] 接收 body 错误: \(error)")
                connection.cancel()
                return
            }

            var newBuffer = buffer
            if let data = data {
                newBuffer.append(data)
            }

            let headerEnd = self.findHeaderEnd(in: newBuffer)!
            let bodyData = newBuffer.suffix(from: headerEnd + 4)
            let contentLength = request.headers["content-length"].flatMap { Int($0) } ?? 0

            if bodyData.count < contentLength {
                self.receiveRequestBody(connection: connection, request: request, buffer: newBuffer, remaining: contentLength - bodyData.count)
            } else {
                request.body = bodyData.prefix(contentLength)
                self.processRequest(request: request, connection: connection)
            }
        }
    }

    // MARK: - 请求处理

    private func processRequest(request: HTTPRequest, connection: NWConnection) {
        print("[LocalHTTPServer] -> \(request.method) \(request.path)")

        // API 代理
        if request.path.hasPrefix("/api/fish/") || request.path == "/api/fish" {
            proxyAPIRequest(request: request, connection: connection)
            return
        }

        // 静态文件
        serveStaticFile(request: request, connection: connection)
    }

    // MARK: - 静态文件服务

    private func serveStaticFile(request: HTTPRequest, connection: NWConnection) {
        var path = request.path
        if path == "/" || path.isEmpty {
            path = "/index.html"
        }

        // 安全检查：防止路径遍历
        path = path.replacingOccurrences(of: "..", with: "")
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        guard let fileURL = Bundle.main.url(forResource: "web/\(path)", withExtension: nil) else {
            print("[LocalHTTPServer] 文件未找到: web/\(path)")
            sendError(connection: connection, status: 404, message: "Not Found")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let contentType = mimeType(for: path)
            sendResponse(connection: connection, status: 200, headers: [
                "Content-Type": contentType,
                "Content-Length": "\(data.count)",
                "Cache-Control": "public, max-age=3600",
                "Access-Control-Allow-Origin": "*"
            ], body: data)
        } catch {
            print("[LocalHTTPServer] 读取文件失败: \(error)")
            sendError(connection: connection, status: 500, message: "Internal Server Error")
        }
    }

    // MARK: - API 代理

    private func proxyAPIRequest(request: HTTPRequest, connection: NWConnection) {
        // /api/fish/v1/tts -> https://api.fish.audio/v1/tts
        let targetPath = request.path.replacingOccurrences(of: "/api/fish", with: "")
        let query = request.query ?? ""
        var urlString = "https://api.fish.audio\(targetPath)"
        if !query.isEmpty {
            urlString += "?\(query)"
        }

        guard let url = URL(string: urlString) else {
            sendError(connection: connection, status: 400, message: "Bad URL")
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = 120

        // 复制请求头（跳过 hop-by-hop 和 host）
        for (key, value) in request.headers {
            let lowerKey = key.lowercased()
            if lowerKey != "host" && lowerKey != "connection" &&
               lowerKey != "content-length" && lowerKey != "accept-encoding" {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }

        // 复制请求体
        if !request.body.isEmpty {
            urlRequest.httpBody = request.body
        }

        print("[Proxy] -> \(request.method) \(url.absoluteString)")

        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                print("[Proxy] 请求失败: \(error.localizedDescription)")
                let errData = Data(error.localizedDescription.utf8)
                self.sendResponse(connection: connection, status: 502, headers: [
                    "Content-Type": "text/plain; charset=utf-8",
                    "Content-Length": "\(errData.count)"
                ], body: errData)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.sendError(connection: connection, status: 502, message: "Bad Gateway")
                return
            }

            print("[Proxy] <- \(httpResponse.statusCode) (\(data?.count ?? 0) bytes)")

            let respData = data ?? Data()
            var respHeaders: [String: String] = [
                "Content-Length": "\(respData.count)",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS, PATCH",
                "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With"
            ]

            // 复制响应头
            for (key, value) in httpResponse.allHeaderFields {
                if let keyStr = key as? String, let valueStr = value as? String {
                    let lowerKey = keyStr.lowercased()
                    if lowerKey != "content-length" && lowerKey != "connection" &&
                       lowerKey != "transfer-encoding" && lowerKey != "content-encoding" {
                        respHeaders[keyStr] = valueStr
                    }
                }
            }

            self.sendResponse(connection: connection, status: httpResponse.statusCode, headers: respHeaders, body: respData)
        }.resume()
    }

    // MARK: - HTTP 响应发送

    private func sendResponse(connection: NWConnection, status: Int, headers: [String: String], body: Data) {
        let statusText = httpStatusText(status)
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Server: VoiceReaderLocal/1.0\r\n"
        for (key, value) in headers {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"

        var responseData = Data(response.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { [weak connection] error in
            if let error = error {
                print("[LocalHTTPServer] 发送响应错误: \(error)")
            }
            connection?.cancel()
        })
    }

    private func sendError(connection: NWConnection, status: Int, message: String) {
        let body = Data(message.utf8)
        sendResponse(connection: connection, status: status, headers: [
            "Content-Type": "text/plain; charset=utf-8",
            "Content-Length": "\(body.count)"
        ], body: body)
    }

    // MARK: - HTTP 解析工具

    private func findHeaderEnd(in data: Data) -> Int? {
        let pattern = Data("\r\n\r\n".utf8)
        return data.range(of: pattern)?.lowerBound
    }

    private func parseHTTPRequest(headerData: Data) -> HTTPRequest? {
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        // 请求行: GET /path?query HTTP/1.1
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }

        let method = requestLine[0]
        let fullPath = requestLine[1]

        // 分离 path 和 query
        var path = fullPath
        var query: String?
        if let queryRange = fullPath.range(of: "?") {
            path = String(fullPath[..<queryRange.lowerBound])
            query = String(fullPath[queryRange.upperBound...])
        }

        // 解析请求头
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let separatorRange = line.range(of: ": ") {
                let key = String(line[..<separatorRange.lowerBound]).lowercased()
                let value = String(line[separatorRange.upperBound...])
                headers[key] = value
            }
        }

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: Data())
    }

    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "m4a": return "audio/mp4"
        case "webmanifest", "manifest": return "application/manifest+json"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "eot": return "application/vnd.ms-fontobject"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    private func httpStatusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 408: return "Request Timeout"
        case 413: return "Payload Too Large"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "Unknown"
        }
    }
}

// MARK: - HTTP 请求模型

class HTTPRequest {
    let method: String
    let path: String
    let query: String?
    var headers: [String: String]
    var body: Data

    init(method: String, path: String, query: String?, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}
