//
//  ViewController.swift
//  糖果大冒险
//
//  WKWebView 容器，加载原版 index.html 网页游戏
//  不修改任何网页游戏逻辑，只提供原生容器环境
//

import UIKit
import WebKit
import AVFoundation

class ViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, UIScrollViewDelegate {

    // MARK: - WKWebView
    private var webView: WKWebView!

    // 文件选择回调
    private var filePickerCompletion: (([URL]?) -> Void)?

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()

        setupWebView()
        loadLocalHTML()
    }

    // MARK: - 配置 WKWebView
    private func setupWebView() {
        // WKWebView 配置
        let config = WKWebViewConfiguration()

        // 允许 JavaScript
        let prefs = WKPreferences()
        prefs.javaScriptEnabled = true
        config.preferences = prefs

        // 允许内联媒体播放（不强制全屏）
        config.allowsInlineMediaPlayback = true

        // 允许媒体自动播放（不需要用户手势）
        if #available(iOS 10.0, *) {
            config.mediaTypesRequiringUserActionForPlayback = []
        }

        // 允许图片媒体播放
        if #available(iOS 13.0, *) {
            // 无需额外配置
        }

        // 创建 WKWebView
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.backgroundColor = .white
        webView.isOpaque = true

        // 禁止用户双指缩放（网页 viewport 已设置 user-scalable=no）
        webView.scrollView.delegate = self
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // 适配 Safe Area（网页自己用 env(safe-area-inset-*) 处理）
        if #available(iOS 11.0, *) {
            webView.scrollView.contentInsetAdjustmentBehavior = .never
        }

        view.addSubview(webView)
    }

    // MARK: - 加载本地 index.html
    private func loadLocalHTML() {
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            print("❌ 找不到 index.html，请确认已添加到工程的 Copy Bundle Resources")
            showErrorAlert(message: "找不到游戏文件 index.html\n\n请确认 index.html 已添加到工程")
            return
        }
        
        print("✅ 找到 index.html: \(htmlURL.path)")
        
        // 检查文件是否可读
        guard let htmlData = try? Data(contentsOf: htmlURL) else {
            print("❌ 无法读取 index.html")
            showErrorAlert(message: "无法读取游戏文件")
            return
        }
        print("✅ index.html 文件大小: \(htmlData.count) 字节")
        
        // 使用 loadFileURL 直接加载本地文件（比 loadHTMLString 更可靠）
        // allowingReadAccessTo 允许 WKWebView 访问同目录下的资源文件
        let baseURL = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
        
        print("✅ 开始加载 index.html...")
    }

    // MARK: - 禁止缩放（UIScrollViewDelegate）
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return nil
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ 网页加载完成")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("⚠️ 网页加载失败: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("⚠️ 网页初始加载失败: \(error.localizedDescription)")
    }

    // 允许所有 HTTPS 请求（Supabase 需要）
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate: 麦克风/摄像头权限（iOS 15+）
    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        print("📹 网页请求媒体权限，类型: \(type.rawValue)")

        // 请求 iOS 系统麦克风权限
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("✅ 麦克风权限已授予")
                    decisionHandler(.grant)
                } else {
                    print("❌ 麦克风权限被拒绝")
                    decisionHandler(.deny)
                    self.showMicrophonePermissionAlert()
                }
            }
        }
    }

    // MARK: - WKUIDelegate: 文件选择（上传音乐）
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        print("📁 网页请求文件选择")
        filePickerCompletion = completionHandler

        let alert = UIAlertController(
            title: "选择文件",
            message: "请选择要上传的音乐文件",
            preferredStyle: .actionSheet
        )

        // 从文件应用选择
        alert.addAction(UIAlertAction(title: "文件", style: .default) { [weak self] _ in
            self?.presentDocumentPicker()
        })

        // 从照片库选择（如果允许）
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            alert.addAction(UIAlertAction(title: "照片库", style: .default) { [weak self] _ in
                self?.presentPhotoPicker()
            })
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.filePickerCompletion?(nil)
            self?.filePickerCompletion = nil
        })

        // iPad 适配
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        present(alert, animated: true)
    }

    // MARK: - 文件选择器
    private func presentDocumentPicker() {
        let documentPicker = UIDocumentPickerViewController(
            documentTypes: [
                "public.audio",
                "public.mp3",
                "com.microsoft.waveform-audio",
                "public.mpeg-4-audio",
                "org.xiph.ogg.audio",
                "org.webmproject.webm",
                "public.data"
            ],
            in: .import
        )
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    private func presentPhotoPicker() {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.audio", "public.movie"]
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - 警告弹窗
    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: "错误",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showMicrophonePermissionAlert() {
        let alert = UIAlertController(
            title: "需要麦克风权限",
            message: "糖果大冒险需要使用麦克风来录制语音消息。\n\n请在「设置」→「糖果大冒险」中开启麦克风权限。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 内存警告
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        print("⚠️ 收到内存警告")
    }
}

// MARK: - UIDocumentPickerDelegate
extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        print("✅ 已选择文件: \(urls)")
        filePickerCompletion?(urls)
        filePickerCompletion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        print("⚠️ 文件选择已取消")
        filePickerCompletion?(nil)
        filePickerCompletion = nil
    }
}

// MARK: - UIImagePickerControllerDelegate
extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        picker.dismiss(animated: true) { [weak self] in
            if let mediaURL = info[.mediaURL] as? URL {
                print("✅ 已选择媒体文件: \(mediaURL)")
                self?.filePickerCompletion?([mediaURL])
            } else {
                self?.filePickerCompletion?(nil)
            }
            self?.filePickerCompletion = nil
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [weak self] in
            self?.filePickerCompletion?(nil)
            self?.filePickerCompletion = nil
        }
    }
}
