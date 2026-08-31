//
//  AppDelegate.swift
//  糖果大冒险
//
//  WKWebView 容器 App，加载原版 index.html 网页游戏
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 创建主窗口
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .white

        // 设置根视图控制器为 WKWebView 容器
        let viewController = ViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        return true
    }

    // 仅支持竖屏
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
