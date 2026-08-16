#!/bin/bash
# 把 dist/刘海岛.app 打包成可分发的 DMG 安装镜像。
# 用法：./scripts/make-dmg.sh [版本号]（需要先构建，或让它自动构建）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
APP="dist/刘海岛.app"
# 下载文件名保持 ASCII，避免浏览器与命令行处理中文时出现编码问题。
if [ -n "${VERSION}" ]; then
	DMG="dist/NotchIsland-${VERSION}-arm64.dmg"
else
	DMG="dist/NotchIsland-arm64.dmg"
fi

if [ ! -d "${APP}" ]; then
	echo "==> 未找到 ${APP}，先构建"
	./build.sh release
fi

echo "==> 打包 ${DMG}"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

cp -R "${APP}" "${STAGING}/"
# 经典安装布局：拖动应用到旁边的「应用程序」快捷方式即可安装。
ln -s /Applications "${STAGING}/Applications"

rm -f "${DMG}"
hdiutil create -volname "刘海岛" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}" >/dev/null
hdiutil verify "${DMG}" >/dev/null

echo "完成：${DMG}"
ls -lh "${DMG}"
