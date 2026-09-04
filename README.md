# 🎙️ AI 声音朗读器
基于 Fish Audio API 的文字转语音 Web 应用，支持零样本声音克隆和永久声音模型创建。

## 功能
- ✅ 文字转语音（TTS），支持长文本自动分段
- ✅ 零样本声音克隆（上传参考音频 + 文字，无需创建音色）
- ✅ 创建永久声音ID（上传音频 → 生成 voice_id → 保存到 Fish 账号）
- ✅ 声音 ID 模式（使用已有的 reference_id）
- ✅ 情绪标签（开心/悲伤/生气/平静/耳语/强调/兴奋/轻柔，点击插入文本）
- ✅ 高级设置（表现力 temperature、音质模式 latency、响度归一化）
- ✅ 中文文本预处理（数字转中文、标点优化、句末补标点）
- ✅ 语速调节（0.5x - 2.0x）
- ✅ 收藏声音（本地保存声音ID，一键切换）
- ✅ 在线播放 + MP3 下载
- ✅ 最近生成记录（IndexedDB 本地保存，支持播放/下载）
- ✅ 自定义音效（生成按钮、情绪按钮专属音效）
- ✅ PWA 支持（可添加到主屏幕）
- ✅ 移动端适配，禁止页面缩放

## 项目结构
```
.
├── public/                    # 前端静态文件
│   ├── index.html            # 主页面（包含所有 JS/CSS）
│   ├── manifest.json         # PWA 配置
│   ├── bg.jpg                # 背景图
│   ├── icon-*.png            # 应用图标（180/192/512）
│   ├── gen-sound.mp3         # 生成按钮自定义音效
│   ├── happy.mp3             # 情绪音效：开心
│   ├── sad.mp3               # 情绪音效：悲伤
│   ├── angry.mp3             # 情绪音效：生气
│   ├── calm.mp3              # 情绪音效：平静
│   ├── whisper.mp3           # 情绪音效：耳语
│   ├── emphasis.mp3          # 情绪音效：强调
│   ├── excited.mp3           # 情绪音效：兴奋
│   ├── soft.mp3              # 情绪音效：轻柔
│   └── click.mp3             # 点击音效（备用）
├── functions/
│   └── api/fish/
│       └── [[path]].js       # Cloudflare Pages Functions 代理（绕开 CORS）
└── README.md
```

## 部署到 Cloudflare Pages

### 方法一：Wrangler CLI（推荐）
```bash
# 安装 Wrangler
npm install -g wrangler

# 登录（浏览器授权）
wrangler login

# 创建项目
wrangler pages project create gjlwsws666

# 部署（会自动上传 functions 目录）
wrangler pages deploy public --project-name=gjlwsws666
```

### 方法二：Dashboard 上传
1. 打开 https://dash.cloudflare.com
2. Workers & Pages → Create → Pages → Upload assets
3. 把 `public/` 目录拖进去
4. Functions 会自动识别 `functions/` 目录

## 使用方法
1. 打开网站，输入 Fish Audio API Key（在 https://fish.audio 获取）
2. 选择声音来源：
   - **声音 ID**：输入已有的 reference_id，或点「🎙️ 创建声音ID」上传音频生成
   - **上传参考音频**：上传音频 + 填写音频中的文字 → 点「确认使用此声音」（零样本，不保存到账号）
3. 输入朗读文字，可插入情绪标签
4. （可选）点开高级设置，调节表现力和音质模式
5. 选择语速，点「生成语音」
6. 播放或下载 MP3

## API 代理说明
由于 Fish Audio API 不支持浏览器直接跨域调用（CORS），项目使用 Cloudflare Pages Functions 做后端代理：

| 前端请求 | 代理到 | 用途 |
|---------|--------|------|
| `GET /api/fish/wallet/self/api-credit` | `https://api.fish.audio/wallet/self/api-credit` | 验证 API Key |
| `POST /api/fish/v1/tts` | `https://api.fish.audio/v1/tts` | 语音合成 |
| `POST /api/fish/model` | `https://api.fish.audio/model` | 创建永久声音模型 |
| `POST /api/fish/voices` | `https://fishaudio.org/api/open/v1/voices` | 备用创建声音接口 |
| `GET /api/fish/v1/models` | `https://api.fish.audio/wallet/self/api-credit` | 兼容旧版 key 验证 |

## Fish Audio API 参数
- **模型**：s2.1-pro-free（默认）
- **speed**：0.5 - 2.0，语速
- **temperature**：0.0 - 1.0，表现力（0.3平稳/0.7自然/0.9丰富）
- **latency**：normal高质量 / balanced均衡 / low快速
- **normalize_loudness**：true，响度归一化
- **情绪标签**：文本中插入 `[happy]`、`[sad]` 等方括号标签

## 注意事项
- API Key 仅保存在浏览器 localStorage 中
- 生成的音频保存在浏览器 IndexedDB 中，清除浏览器数据会丢失
- 零样本克隆的参考文字越准确，合成效果越好
- 创建声音ID会消耗 Fish 账号额度并占用私有声音槽位
- 请仅使用本人或已获得授权的声音样本

## 线上地址
https://gjlwsws666.pages.dev

---

## 📱 iOS App 封装

本项目已封装为原生 iOS App，可安装到 iPhone 使用。

### 架构
- **WKWebView** 加载本地打包的 Web 页面（静态资源在 App Bundle 内，离线可用）
- **GCDWebServer** 本地 HTTP 服务器，提供静态文件 + 代理 Fish Audio API
- **原生 API 代理**：`/api/fish/*` → `https://api.fish.audio/*`，彻底绕开 CORS
- **JS 桥接**：MP3 下载通过原生端保存到文件并分享

### 功能保留
- ✅ Fish Audio TTS 文字转语音
- ✅ 零样本声音克隆（上传参考音频）
- ✅ 创建永久声音 ID
- ✅ 声音 ID 模式
- ✅ 情绪标签
- ✅ 语速控制（0.5x - 2.0x）
- ✅ 在线播放
- ✅ MP3 下载（原生分享面板保存）
- ✅ 历史记录（IndexedDB 本地保存）
- ✅ 收藏声音（localStorage）

### iOS 兼容性修复
- **CORS**：原生端代理所有 API 请求，WebView 无跨域问题
- **音频播放**：`AVAudioSession` 配置为 playback 类别，静音模式下也能播放
- **MP3 下载**：通过 `WKScriptMessageHandler` 桥接，原生端保存文件并弹出 `UIActivityViewController`
- **IndexedDB**：WKWebView 原生支持，数据存储在 App 沙盒
- **HTTPS**：本地服务器用 `http://localhost`，已在 Info.plist 中允许本地网络
- **API 请求**：支持 GET/POST/PUT/DELETE/OPTIONS/PATCH，支持 multipart/form-data（声音克隆上传）

### 构建方式
项目使用 **XcodeGen** 生成 Xcode 工程，**GitHub Actions** 自动构建。

#### 本地构建
```bash
# 安装 XcodeGen
brew install xcodegen

# 生成 Xcode 工程
xcodegen generate

# 打开 Xcode
open "AI声音朗读器.xcodeproj"

# 或命令行构建（未签名）
xcodebuild -project "AI声音朗读器.xcodeproj" \
  -scheme "AI声音朗读器" \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO build
```

#### GitHub Actions 自动构建
每次 push 到主分支会自动触发构建，产出未签名 IPA。
- 构建产物在 Actions 页面的 Artifacts 中下载
- 未签名 IPA 可直接用 **TrollStore** 安装（永久不掉签）
- 也可用 Sideloadly / AltStore 侧载（7天掉签）

### 项目结构
```
.
├── public/                    # Web 前端（网页部署用）
├── functions/                 # Cloudflare Pages Functions（网页部署用）
├── ios/
│   ├── App/
│   │   ├── AppDelegate.swift       # 应用入口，音频会话配置
│   │   ├── SceneDelegate.swift     # 场景管理
│   │   ├── ViewController.swift    # WKWebView 管理 + JS 桥接
│   │   ├── LocalHTTPServer.swift   # 本地 HTTP 服务器 + API 代理
│   │   └── Info.plist              # 应用配置
│   ├── Assets.xcassets/            # App 图标和资源
│   └── web/                        # 打包进 App 的 Web 静态文件
├── project.yml                # XcodeGen 项目定义
└── .github/workflows/
    └── build-ios.yml          # GitHub Actions 自动构建
```

### 签名说明
当前构建为**未签名 IPA**，原因：
- 未配置苹果开发者账号（Apple Developer Program，$99/年）
- 未在 GitHub Secrets 中配置签名证书（`.p12`）和描述文件（`.mobileprovision`）

如需签名 IPA，需要：
1. 加入苹果开发者计划
2. 创建 iOS Distribution 证书和 App Store / Ad Hoc 描述文件
3. 在 GitHub 仓库 Settings → Secrets and variables → Actions 中添加：
   - `IOS_CODE_SIGN_IDENTITY`：签名身份（如 `iPhone Distribution: XXX`）
   - `IOS_DEVELOPMENT_TEAM`：团队 ID
   - `IOS_PROVISIONING_PROFILE`：描述文件（base64 编码）
   - `IOS_CERTIFICATE`：证书 p12 文件（base64 编码）
   - `IOS_CERTIFICATE_PASSWORD`：证书密码

### 注意事项
- App 首次启动需要联网（调用 Fish Audio API），静态资源已打包离线可用
- API Key 保存在 App 沙盒的 localStorage 中，卸载 App 会丢失
- 生成的历史记录保存在 IndexedDB 中，卸载 App 会丢失
- MP3 下载通过 iOS 分享面板，可保存到"文件"App 或其他应用
- 支持 iOS 14.0 及以上版本
