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

# --- 3) ksmbd 6.12 死锁 / RCU stall 修复（2026-09-26 新增） ---
# 上游 OpenWrt issue #24738，修复 commit a42896bebfcc287ed1e61d820a888e33b1eb80ce
# 'ksmbd: harden file lifetime during session teardown'
# 症状：Windows 打开共享文件 -> ksmbd 在 smb2_open / ksmbd_smb_check_shared_mode
#       里 list 损坏并死循环 -> rcu self-detected stall 每 180 秒复发 ->
#       load 冲到 6.98（4 核占满）-> WiFi 关联/四次握手全超时（设备提示密码错误），
#       且该自旋在内核态杀不掉，只能重启路由器；原厂用 Samba4 用户态服务所以没这毛病。
# 做法：编译前把上游 6.12 专用 backport 放进 backport-6.12/，由内核构建自动应用。
#       下载失败即中止构建，避免编出仍然会死锁的固件。
KSMBD_DIR='./target/linux/generic/backport-6.12'
KSMBD_PATCH='901-ksmbd-harden-file-lifetime-during-session-teardown.patch'
KSMBD_URL='https://raw.githubusercontent.com/openwrt/openwrt/d9f4284a719da3c391876774219b5be0b5fea2a0/target/linux/generic/backport-6.12/501-v7.1-ksmbd-harden-file-lifetime-during-session-teardown.patch'

if [ -d $KSMBD_DIR ]; then
	got=0
	for attempt in 1 2 3; do
		if curl -fsSL --retry 3 --connect-timeout 20 $KSMBD_URL -o $KSMBD_DIR/$KSMBD_PATCH; then
			got=1
			break
		fi
		sleep 5
	done
	if [ $got != 1 ] || ! head -n 1 $KSMBD_DIR/$KSMBD_PATCH | grep -q '^From '; then
		echo '[PRIVATE] FATAL: ksmbd 6.12 patch download failed, aborting build.' >&2
		exit 1
	fi
	echo [PRIVATE] ksmbd 6.12 patch installed: $KSMBD_DIR/$KSMBD_PATCH
	grep -m1 '^Subject:' $KSMBD_DIR/$KSMBD_PATCH || true
	wc -l $KSMBD_DIR/$KSMBD_PATCH || true
else
	echo '[PRIVATE] WARN: backport-6.12 not found, ksmbd patch not injected.' >&2
fi

true
