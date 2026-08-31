#!/bin/bash
# 把 dist/刘海岛.app 打包成可分发的 DMG 安装镜像。
# 用法：./scripts/make-dmg.sh [版本号]（需要先构建，或让它自动构建）
#
# 发版镜像默认打通用二进制，Intel 机型可以直接用；
# 只想要本机架构时设 NOTCHISLAND_UNIVERSAL=0。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
APP="dist/刘海岛.app"
EXECUTABLE="${APP}/Contents/MacOS/NotchIsland"

if [ ! -d "${APP}" ]; then
	echo "==> 未找到 ${APP}，先构建"
	NOTCHISLAND_UNIVERSAL="${NOTCHISLAND_UNIVERSAL:-1}" ./build.sh release
fi

# 架构后缀按产物实际情况取，不写死：镜像名如果和里面的东西不一致，
# Intel 用户会因为看到 arm64 而直接跳过一个其实能用的包。
ARCHS="$(lipo -archs "${EXECUTABLE}")"
if [ "$(echo "${ARCHS}" | wc -w)" -gt 1 ]; then
	ARCH_SUFFIX="universal"
else
	ARCH_SUFFIX="${ARCHS}"
fi
echo "==> 产物架构：${ARCHS}（后缀 ${ARCH_SUFFIX}）"

# 下载文件名保持 ASCII，避免浏览器与命令行处理中文时出现编码问题。
if [ -n "${VERSION}" ]; then
	DMG="dist/NotchIsland-${VERSION}-${ARCH_SUFFIX}.dmg"
else
	DMG="dist/NotchIsland-${ARCH_SUFFIX}.dmg"
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
