#!/bin/bash
# ============================================================
# 糖果大冒险 - 一键构建 IPA 脚本
# ============================================================
# 使用方法:
#   ./build_ipa.sh [选项]
#
# 选项:
#   -t, --team-id <TEAM_ID>       Apple Developer Team ID (必填)
#   -b, --bundle-id <BUNDLE_ID>   Bundle Identifier (可选，默认 com.example.candyadventure)
#   -m, --method <METHOD>          分发方式: development / ad-hoc / app-store (默认 development)
#   -o, --output <DIR>             输出目录 (默认 ./output)
#   -h, --help                     显示帮助
#
# 示例:
#   ./build_ipa.sh -t ABC1234567 -m development
#   ./build_ipa.sh -t ABC1234567 -b com.myapp.candy -m ad-hoc -o ~/Desktop/ipa
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
TEAM_ID=""
BUNDLE_ID="com.example.candyadventure"
EXPORT_METHOD="development"
OUTPUT_DIR="./output"
PROJECT_NAME="糖果大冒险"
SCHEME="糖果大冒险"
CONFIGURATION="Release"

# 显示帮助
show_help() {
    echo "========================================"
    echo "  糖果大冒险 - 一键构建 IPA 脚本"
    echo "========================================"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -t, --team-id <TEAM_ID>       Apple Developer Team ID (必填)"
    echo "  -b, --bundle-id <BUNDLE_ID>   Bundle Identifier (默认: com.example.candyadventure)"
    echo "  -m, --method <METHOD>          分发方式: development / ad-hoc / app-store (默认: development)"
    echo "  -o, --output <DIR>             输出目录 (默认: ./output)"
    echo "  -h, --help                     显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 -t ABC1234567"
    echo "  $0 -t ABC1234567 -b com.myapp.candy -m ad-hoc"
    echo ""
    echo "如何获取 Team ID:"
    echo "  1. 登录 https://developer.apple.com/account"
    echo "  2. 进入 Membership 页面"
    echo "  3. Team ID 显示在页面上"
    echo ""
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        -b|--bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        -m|--method)
            EXPORT_METHOD="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            ;;
    esac
done

# 检查必填参数
if [ -z "$TEAM_ID" ]; then
    echo -e "${RED}错误: Team ID 是必填参数${NC}"
    echo ""
    echo "使用 -h 查看帮助"
    echo ""
    echo "如何获取 Team ID:"
    echo "  1. 登录 https://developer.apple.com/account"
    echo "  2. 进入 Membership 页面"
    echo "  3. Team ID 显示在页面上"
    exit 1
fi

# 检查是否在 macOS 上
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}错误: 此脚本必须在 macOS 上运行${NC}"
    echo "当前系统: $(uname)"
    exit 1
fi

# 检查 Xcode 是否安装
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}错误: 未找到 Xcode，请先安装 Xcode${NC}"
    echo "从 App Store 下载 Xcode"
    exit 1
fi

echo ""
echo "========================================"
echo "  糖果大冒险 - 开始构建 IPA"
echo "========================================"
echo ""
echo -e "${BLUE}配置信息:${NC}"
echo "  Team ID:        $TEAM_ID"
echo "  Bundle ID:      $BUNDLE_ID"
echo "  分发方式:       $EXPORT_METHOD"
echo "  输出目录:       $OUTPUT_DIR"
echo "  配置:           $CONFIGURATION"
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT_FILE="$PROJECT_DIR/CandyAdventure.xcodeproj"

# 检查工程文件
if [ ! -d "$PROJECT_FILE" ]; then
    echo -e "${RED}错误: 未找到工程文件 $PROJECT_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}工程文件:${NC} $PROJECT_FILE"
echo ""

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# ============================================================
# 步骤 1: 清理构建
# ============================================================
echo -e "${YELLOW}[1/5] 清理构建...${NC}"
xcodebuild clean \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    2>&1 | tail -5

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}清理失败${NC}"
    exit 1
fi
echo -e "${GREEN}清理完成${NC}"
echo ""

# ============================================================
# 步骤 2: 构建 Archive
# ============================================================
echo -e "${YELLOW}[2/5] 构建 Archive (这可能需要几分钟)...${NC}"
ARCHIVE_PATH="$OUTPUT_DIR/${PROJECT_NAME}.xcarchive"

xcodebuild archive \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
    CODE_SIGN_STYLE="Automatic" \
    2>&1 | tail -20

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}Archive 构建失败${NC}"
    echo ""
    echo "可能的原因:"
    echo "  1. Team ID 不正确"
    echo "  2. 没有登录 Apple Developer 账号"
    echo "  3. 证书问题"
    echo ""
    echo "请在 Xcode 中打开工程，手动设置签名后重试"
    exit 1
fi
echo -e "${GREEN}Archive 构建完成${NC}"
echo "Archive 路径: $ARCHIVE_PATH"
echo ""

# ============================================================
# 步骤 3: 生成 ExportOptions.plist
# ============================================================
echo -e "${YELLOW}[3/5] 生成导出配置...${NC}"
EXPORT_OPTIONS="$OUTPUT_DIR/ExportOptions.plist"

cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>$EXPORT_METHOD</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>thinning</key>
    <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

echo -e "${GREEN}导出配置生成完成${NC}"
echo "配置路径: $EXPORT_OPTIONS"
echo ""

# ============================================================
# 步骤 4: 导出 IPA
# ============================================================
echo -e "${YELLOW}[4/5] 导出 IPA...${NC}"
EXPORT_PATH="$OUTPUT_DIR/ipa_export"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>&1 | tail -20

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}IPA 导出失败${NC}"
    echo ""
    echo "可能的原因:"
    echo "  1. 分发方式不支持当前账号类型"
    echo "  2. 免费账号只能使用 development 方式"
    echo "  3. 设备未注册到开发者账号"
    echo ""
    echo "免费 Apple ID 请使用: -m development"
    exit 1
fi
echo -e "${GREEN}IPA 导出完成${NC}"
echo ""

# ============================================================
# 步骤 5: 查找并复制 IPA
# ============================================================
echo -e "${YELLOW}[5/5] 整理输出文件...${NC}"

IPA_FILE=$(find "$EXPORT_PATH" -name "*.ipa" -type f | head -1)

if [ -z "$IPA_FILE" ]; then
    echo -e "${RED}未找到生成的 IPA 文件${NC}"
    echo "导出目录: $EXPORT_PATH"
    ls -la "$EXPORT_PATH"
    exit 1
fi

FINAL_IPA="$OUTPUT_DIR/${PROJECT_NAME}.ipa"
cp "$IPA_FILE" "$FINAL_IPA"

echo -e "${GREEN}IPA 文件已生成!${NC}"
echo ""
echo "========================================"
echo "  构建完成!"
echo "========================================"
echo ""
echo -e "${GREEN}IPA 文件路径:${NC}"
echo "  $FINAL_IPA"
echo ""
echo -e "${BLUE}文件信息:${NC}"
ls -lh "$FINAL_IPA"
echo ""
echo -e "${BLUE}构建参数:${NC}"
echo "  Team ID:     $TEAM_ID"
echo "  Bundle ID:   $BUNDLE_ID"
echo "  分发方式:    $EXPORT_METHOD"
echo ""
echo -e "${YELLOW}下一步:${NC}"
echo "  1. 将 IPA 文件传输到 iPhone"
echo "  2. 使用 Xcode / Apple Configurator / AltStore 等工具安装"
echo ""
