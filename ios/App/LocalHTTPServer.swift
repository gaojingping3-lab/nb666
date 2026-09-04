import Foundation
import GCDWebServer

/// 本地 HTTP 服务器
/// - 提供 App Bundle 中的 web 静态文件（index.html、图标、音效等）
/// - 代理 /api/fish/* 请求到 https://api.fish.audio/*，彻底绕开 CORS
class LocalHTTPServer {

    private var server: GCDWebServer!
    private(set) var port: UInt = 0

    func start() -> UInt {
        server = GCDWebServer()

        // 1. 静态文件：从 Bundle 的 web 目录提供
        if let webPath = Bundle.main.path(forResource: "web", ofType: nil) {
            server.addGETHandler(
                forBasePath: "/",
                directoryPath: webPath,
                indexFilename: "index.html",
                cacheAge: 3600,
                allowRangeRequests: true
            )
            print("[LocalHTTPServer] 静态文件目录: \(webPath)")
        } else {
            print("[LocalHTTPServer] ⚠️ 未找到 web 资源目录")
        }

        // 2. API 代理：拦截所有 /api/fish/* 请求（支持 GET/POST/PUT/DELETE/OPTIONS）
        let methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
        for method in methods {
            server.addHandler(
                forMethod: method,
                pathRegex: "/api/fish/.*",
                request: GCDWebServerRequest.self
            ) { [weak self] request in
                return self?.proxyRequest(request) ?? GCDWebServerResponse(statusCode: 502)
            }
        }

        // 3. 启动服务器（端口 0 = 自动分配可用端口）
        server.start(withPort: 0, bonjourName: nil)
        port = server.port
        print("[LocalHTTPServer] 已启动: http://localhost:\(port)")
        return port
    }

    func stop() {
        server?.stop()
        print("[LocalHTTPServer] 已停止")
    }

    // MARK: - API 代理核心逻辑

    private func proxyRequest(_ request: GCDWebServerRequest) -> GCDWebServerResponse? {
        // 构建目标 URL：/api/fish/v1/tts -> https://api.fish.audio/v1/tts
        let path = request.url.path.replacingOccurrences(of: "/api/fish", with: "")
        let query = request.url.query ?? ""
        var urlString = "https://api.fish.audio\(path)"
        if !query.isEmpty { urlString += "?\(query)" }

        guard let url = URL(string: urlString) else {
            print("[Proxy] URL 无效: \(urlString)")
            return GCDWebServerResponse(statusCode: 400)
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

        // 复制请求体（GCDWebServerDataRequest 包含原始 body，包括 multipart/form-data）
        if let dataRequest = request as? GCDWebServerDataRequest {
            urlRequest.httpBody = dataRequest.data
        }

        print("[Proxy] -> \(request.method) \(url.absoluteString)")

        // 同步等待响应（GCDWebServer handler 在后台线程执行，同步等待安全）
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        var responseError: Error?

        URLSession.shared.dataTask(with: urlRequest) { data, resp, error in
            responseData = data
            httpResponse = resp as? HTTPURLResponse
            responseError = error
            semaphore.signal()
        }.resume()

        let timeout = DispatchTime.now() + 120
        _ = semaphore.wait(timeout: timeout)

        // 错误处理
        if let error = responseError {
            print("[Proxy] 请求失败: \(error.localizedDescription)")
            let errData = Data(error.localizedString.utf8)
            let resp = GCDWebServerDataResponse(data: errData, contentType: "text/plain; charset=utf-8")
            resp?.statusCode = 502
            addCORSHeaders(to: resp)
            return resp
        }

        guard let httpResp = httpResponse else {
            print("[Proxy] 无响应")
            return GCDWebServerResponse(statusCode: 502)
        }

        print("[Proxy] <- \(httpResp.statusCode) (\(responseData?.count ?? 0) bytes)")

        // 构建响应
        let data = responseData ?? Data()
        let contentType = httpResp.allHeaderFields["Content-Type"] as? String ?? "application/octet-stream"
        let serverResp = GCDWebServerDataResponse(data: data, contentType: contentType)
        serverResp?.statusCode = httpResp.statusCode

        // 复制响应头（跳过 hop-by-hop）
        for (key, value) in httpResp.allHeaderFields {
            if let keyStr = key as? String, let valueStr = value as? String {
                let lowerKey = keyStr.lowercased()
                if lowerKey != "content-length" && lowerKey != "connection" &&
                   lowerKey != "transfer-encoding" && lowerKey != "content-encoding" {
                    serverResp?.setValue(valueStr, forAdditionalHeader: keyStr)
                }
            }
        }

        // 确保 CORS 头
        addCORSHeaders(to: serverResp)
        return serverResp
    }

    private func addCORSHeaders(to response: GCDWebServerResponse?) {
        response?.setValue("*", forAdditionalHeader: "Access-Control-Allow-Origin")
        response?.setValue("GET, POST, PUT, DELETE, OPTIONS, PATCH", forAdditionalHeader: "Access-Control-Allow-Methods")
        response?.setValue("Content-Type, Authorization, X-Requested-With", forAdditionalHeader: "Access-Control-Allow-Headers")
        response?.setValue("86400", forAdditionalHeader: "Access-Control-Max-Age")
    }
}
