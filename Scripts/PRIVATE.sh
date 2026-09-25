#!/bin/bash
# ============================================================================
#  MT3600BE 自编：私有修正脚本
#  执行时机：由 Scripts/Packages.sh 在最后自动 source，早于 Scripts/Settings.sh
#
#  为什么需要它：
#  上游 Scripts/Settings.sh 会去改
#      ./package/mtk/applications/mtwifi-cfg/files/mtwifi.sh
#  但 chasey-dev 的 25.12-dev-wifi7 分支已经把 Lua 版 mtwifi-cfg 换成了
#  mtwifi-cfg-ucode，这个文件不存在，sed 必然报 "No such file or directory"。
#  GitHub Actions 的 run 步骤是 bash -eo pipefail，这个非 0 一旦传到外层，
#  就会在真正开始编译之前把 workflow 打断。
#
#  这里先把路径补出来（内容留空），让上游那些 sed 变成无害的空操作 ——
#  好处是「不需要改动上游任何文件」，以后 Sync fork 不会冲突。
#  （其余被 sed 的目标：feeds/luci/collections、luci-mod-system/flash.js、
#    luci-mod-status/10_system.js、base-files/bin/config_generate，都已确认存在。）
# ============================================================================

mkdir -p ./package/mtk/applications/mtwifi-cfg/files 2>/dev/null || true
if [ ! -f ./package/mtk/applications/mtwifi-cfg/files/mtwifi.sh ]; then
	: > ./package/mtk/applications/mtwifi-cfg/files/mtwifi.sh 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 顺带把默认 WiFi 名/密码改成 workflow 里配的参数。
# wifi7 分支的无线配置由主线 wifi-scripts 的 mac80211.uc 生成，兜底默认 SSID
# 是 "ImmortalWrt"；这里只替换兜底字面量，如果板级 profile / board.json 里
# 已经有 defaults，则完全不受影响。
# ---------------------------------------------------------------------------
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_UC" ]; then
	sed -i "s/defaults?.ssid || \"ImmortalWrt\"/defaults?.ssid || \"$WRT_SSID\"/g" "$WIFI_UC" 2>/dev/null || true
	sed -i "s/defaults?.encryption || encryption/defaults?.encryption || \"psk2+ccmp\"/g" "$WIFI_UC" 2>/dev/null || true
	sed -i "s/defaults?.key || \"\"/defaults?.key || \"$WRT_WORD\"/g" "$WIFI_UC" 2>/dev/null || true
fi

true
