import UIKit
import WebKit

class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {

    var webView: WKWebView!
    var localServer: LocalHTTPServer!
    private var currentShareFileURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1.0)

        // 1. 启动本地 HTTP 服务器（提供静态文件 + 代理 Fish Audio API）
        localServer = LocalHTTPServer()
        let port = localServer.start()
        print("[ViewController] 本地服务器端口: \(port)")

        // 2. 配置 WKWebView
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // 注入 JS 桥接：保存 MP3 到文件
        let userContent = WKUserContentController()
        userContent.add(self, name: "saveMP3")
        config.userContentController = userContent

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false

        // 自定义 UserAgent，前端据此判断是否在 iOS App 中运行
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 AIVoiceReaderApp/1.0"

        view.addSubview(webView)

        // 3. 加载本地页面
        if let url = URL(string: "http://localhost:\(port)/index.html") {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            webView.load(request)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "saveMP3" else { return }
        guard let body = message.body as? [String: Any],
              let base64 = body["data"] as? String,
              let filename = body["filename"] as? String,
              let data = Data(base64Encoded: base64) else {
            print("[ViewController] saveMP3 参数解析失败")
            return
        }
        saveAndShareMP3(data: data, filename: filename)
    }

    // MARK: - MP3 保存与分享

    private func saveAndShareMP3(data: Data, filename: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: .atomic)
            currentShareFileURL = fileURL

            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activityVC.popoverPresentationController?.sourceView = self.view
            activityVC.popoverPresentationController?.sourceRect =
                CGRect(x: view.bounds.midX, y: view.bounds.maxY - 100, width: 0, height: 0)
            activityVC.completionWithItemsHandler = { [weak self] _, _, _, _ in
                // 分享完成后清理临时文件
                if let url = self?.currentShareFileURL {
                    try? FileManager.default.removeItem(at: url)
                    self?.currentShareFileURL = nil
                }
            }
            present(activityVC, animated: true)
        } catch {
            print("[ViewController] 保存 MP3 失败: \(error)")
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[ViewController] 页面加载完成")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[ViewController] 页面加载失败: \(error)")
    }

    // MARK: - 状态栏

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - 内存警告

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        print("[ViewController] 内存警告")
    }
}
