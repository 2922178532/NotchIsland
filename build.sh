#!/bin/bash
# 编译并打包成可直接运行的「刘海岛.app」
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
# 应用包用中文名，访达里直接显示「刘海岛」——第三方应用没法像系统应用那样
# 走 macOS 内部的本地化名称数据库，访达显示的就是包本身的文件名。
# 可执行文件保持英文，命令行操作不受中文路径影响。
BUNDLE_NAME="刘海岛"
EXECUTABLE_NAME="NotchIsland"
OUTPUT_DIR="dist"
APP_BUNDLE="${OUTPUT_DIR}/${BUNDLE_NAME}.app"

echo "==> 编译（${CONFIGURATION}）"
swift build -c "${CONFIGURATION}" --disable-sandbox
BIN_PATH="$(swift build -c "${CONFIGURATION}" --disable-sandbox --show-bin-path)"

echo "==> 打包 ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"
cp "${BIN_PATH}/${EXECUTABLE_NAME}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
	cp Resources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi
# 本地化显示名：中文系统显示「刘海岛」，其余显示 NotchIsland。
for lproj in Resources/*.lproj; do
	[ -d "${lproj}" ] || continue
	cp -R "${lproj}" "${APP_BUNDLE}/Contents/Resources/"
done

# MIT 要求分发的副本里保留许可证与第三方版权声明。
cp LICENSE "${APP_BUNDLE}/Contents/Resources/LICENSE"
cp THIRD-PARTY-LICENSES.md "${APP_BUNDLE}/Contents/Resources/THIRD-PARTY-LICENSES.md"

echo "==> 签名"
# 默认 ad-hoc 签名：简单可靠，代价是每次重新构建后需要在
# 「系统设置 → 隐私与安全性」里重新授权辅助功能/屏幕录制。
# 如需固定签名身份，设置环境变量 NOTCHISLAND_SIGN_IDENTITY 为证书名。
if [ -n "${NOTCHISLAND_SIGN_IDENTITY:-}" ]; then
	echo "    使用证书：${NOTCHISLAND_SIGN_IDENTITY}"
	codesign --force --timestamp=none --sign "${NOTCHISLAND_SIGN_IDENTITY}" "${APP_BUNDLE}"
else
	codesign --force --sign - --timestamp=none "${APP_BUNDLE}" >/dev/null 2>&1
fi

echo "完成：${APP_BUNDLE}"
