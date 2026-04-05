#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/local/tmp/op12_chg_postfs.log

log_p() { echo "[post-fs $(date '+%H:%M:%S')] $1" >> "$LOG" 2>/dev/null; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

set_prop() {
	local key="$1"
	local val="$2"
	local before

	before=$(getprop "$key")
	resetprop -n "$key" "$val"
	log_p "prop $key: '${before:-<empty>}' -> '$val'"
}

set_prop_dual() {
	local oplus_key="$1"
	local oppo_key="$2"
	local val="$3"

	set_prop "$oplus_key" "$val"
	set_prop "$oppo_key" "$val"
}

detect_profile() {
	local id
	id="$(getprop ro.product.model) $(getprop ro.product.device) $(getprop ro.product.name)"

	if echo "$id" | grep -qiE "OnePlus 12R|CPH2585|CPH2609|aston"; then
		echo "op12r"
	elif echo "$id" | grep -qiE "Ace|PGKM10|PGP110|PJA110|PJG110"; then
		echo "ace"
	elif echo "$id" | grep -qiE "OnePlus 12|CPH2573|PJD110|salami"; then
		echo "op12"
	else
		echo "generic"
	fi
}

read_battery_temp() {
	if [ -f /sys/class/power_supply/battery/temp ]; then
		cat /sys/class/power_supply/battery/temp 2>/dev/null
		return
	fi
	echo ""
}

log_p "=== post-fs-data 充电属性注入开始 ==="
log_p "model=$(getprop ro.product.model), device=$(getprop ro.product.device), region=$(getprop ro.oplus.regionmark)"

if ! has_cmd resetprop; then
	log_p "resetprop 不可用，跳过注入"
	exit 0
fi

BRAND=$(getprop ro.product.brand | tr '[:upper:]' '[:lower:]')
MANUFACTURER=$(getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')

if ! echo "$BRAND $MANUFACTURER" | grep -qE "oneplus|oppo|realme|oplus"; then
	log_p "非 OPlus 生态设备，跳过属性注入"
	exit 0
fi

C2C_MODE_OPLUS=$(getprop persist.sys.oplus.c2c.fix.mode)
C2C_MODE_OPPO=$(getprop persist.sys.oppo.c2c.fix.mode)
if [ -z "$C2C_MODE_OPLUS" ] && [ -z "$C2C_MODE_OPPO" ]; then
	# 默认启用智能防抖模式，避免反复触发 USB 重新连接提示
	set_prop_dual "persist.sys.oplus.c2c.fix.mode" "persist.sys.oppo.c2c.fix.mode" "1"
	log_p "C2C开关默认初始化: mode=1(智能防抖)"
else
	log_p "C2C开关沿用现有配置: oplus=${C2C_MODE_OPLUS:-<empty>}, oppo=${C2C_MODE_OPPO:-<empty>}"
fi

C2C_SCREENGUARD_OPLUS=$(getprop persist.sys.oplus.c2c.screenoff.guard)
C2C_SCREENGUARD_OPPO=$(getprop persist.sys.oppo.c2c.screenoff.guard)
if [ -z "$C2C_SCREENGUARD_OPLUS" ] && [ -z "$C2C_SCREENGUARD_OPPO" ]; then
	# 默认启用锁屏守护，避免灭屏时误触发强动作造成反复重连
	set_prop_dual "persist.sys.oplus.c2c.screenoff.guard" "persist.sys.oppo.c2c.screenoff.guard" "1"
	log_p "锁屏守护默认初始化: screenoff.guard=1"
else
	log_p "锁屏守护沿用现有配置: oplus=${C2C_SCREENGUARD_OPLUS:-<empty>}, oppo=${C2C_SCREENGUARD_OPPO:-<empty>}"
fi

C2C_PORT_POLICY_OPLUS=$(getprop persist.sys.oplus.c2c.port.policy.enable)
C2C_PORT_POLICY_OPPO=$(getprop persist.sys.oppo.c2c.port.policy.enable)
if [ -z "$C2C_PORT_POLICY_OPLUS" ] && [ -z "$C2C_PORT_POLICY_OPPO" ]; then
	# 默认按电脑端口类型自适应，降低个别 PC 端口引发的跳连概率
	set_prop_dual "persist.sys.oplus.c2c.port.policy.enable" "persist.sys.oppo.c2c.port.policy.enable" "1"
	log_p "端口策略默认初始化: port.policy.enable=1"
else
	log_p "端口策略沿用现有配置: oplus=${C2C_PORT_POLICY_OPLUS:-<empty>}, oppo=${C2C_PORT_POLICY_OPPO:-<empty>}"
fi

C2C_FLAP_GUARD_OPLUS=$(getprop persist.sys.oplus.c2c.flap.guard.enable)
C2C_FLAP_GUARD_OPPO=$(getprop persist.sys.oppo.c2c.flap.guard.enable)
if [ -z "$C2C_FLAP_GUARD_OPLUS" ] && [ -z "$C2C_FLAP_GUARD_OPPO" ]; then
	# 默认启用黑屏防抖守护，针对锁屏下反复连接问题
	set_prop_dual "persist.sys.oplus.c2c.flap.guard.enable" "persist.sys.oppo.c2c.flap.guard.enable" "1"
	log_p "黑屏防抖默认初始化: flap.guard.enable=1"
else
	log_p "黑屏防抖沿用现有配置: oplus=${C2C_FLAP_GUARD_OPLUS:-<empty>}, oppo=${C2C_FLAP_GUARD_OPPO:-<empty>}"
fi

PROFILE=$(detect_profile)
BAT_TEMP=$(read_battery_temp)
HOT_MODE=0

if [ -n "$BAT_TEMP" ] && [ "$BAT_TEMP" -ge 430 ] 2>/dev/null; then
	HOT_MODE=1
fi

VOOCPHY=""
QC_BACK=""
CHECK_USB=""

case "$PROFILE" in
	op12)
		VOOCPHY="3"
		QC_BACK="0"
		CHECK_USB="0"
		;;
	op12r)
		VOOCPHY="2"
		QC_BACK="0"
		CHECK_USB="0"
		;;
	ace)
		VOOCPHY="2"
		QC_BACK="1"
		CHECK_USB=""
		;;
	*)
		VOOCPHY=""
		QC_BACK=""
		CHECK_USB=""
		;;
esac

if [ "$HOT_MODE" -eq 1 ]; then
	PPS_DISABLE="1"
	QC_BACK="1"
	log_p "温控策略: 电池温度=${BAT_TEMP}(0.1C) >= 430，启用保守充电策略"
else
	PPS_DISABLE="0"
	log_p "温控策略: 电池温度=${BAT_TEMP:-unknown}(0.1C)，启用常规充电策略"
fi

log_p "设备分档: $PROFILE"

# 安全基础项（所有 OPlus 设备）
set_prop_dual "persist.vendor.oplus.charger.version"  "persist.vendor.oppo.charger.version"  "2"
set_prop_dual "persist.vendor.oplus.charger.mmi_test" "persist.vendor.oppo.charger.mmi_test" "0"
set_prop_dual "persist.sys.oplus.charge.limit.enable" "persist.sys.oppo.charge.limit.enable" "0"

# 温控项（按温度动态）
set_prop_dual "persist.sys.oplus.charge.pps.disable"          "persist.sys.oppo.charge.pps.disable"          "$PPS_DISABLE"
set_prop_dual "persist.vendor.oplus.charger.chg_vooc_qc_back" "persist.vendor.oppo.charger.chg_vooc_qc_back" "$QC_BACK"

# 分档项（仅目标机型）
if [ -n "$VOOCPHY" ]; then
	set_prop_dual "persist.vendor.oplus.charger.voocphy_support" "persist.vendor.oppo.charger.voocphy_support" "$VOOCPHY"
else
	log_p "跳过 voocphy_support 强制下发（generic 档）"
fi

if [ -n "$CHECK_USB" ]; then
	set_prop_dual "persist.vendor.oplus.charger.check_usb" "persist.vendor.oppo.charger.check_usb" "$CHECK_USB"
else
	log_p "跳过 check_usb 强制下发（降低副作用）"
fi

log_p "属性注入完成（分档 + 温控策略）"
