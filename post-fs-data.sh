#!/system/bin/sh
# post-fs-data.sh
# 在文件系统挂载后、system_server 启动前执行
# 此阶段 resetprop 注入，确保充电守护进程读到正确值

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

set_prop_dual "persist.vendor.oplus.charger.version"          "persist.vendor.oppo.charger.version"          "2"
set_prop_dual "persist.vendor.oplus.charger.voocphy_support"  "persist.vendor.oppo.charger.voocphy_support"  "3"
set_prop_dual "persist.vendor.oplus.charger.chg_vooc_qc_back" "persist.vendor.oppo.charger.chg_vooc_qc_back" "0"
set_prop_dual "persist.vendor.oplus.charger.mmi_test"         "persist.vendor.oppo.charger.mmi_test"         "0"
set_prop_dual "persist.vendor.oplus.charger.check_usb"        "persist.vendor.oppo.charger.check_usb"        "0"

set_prop_dual "persist.sys.oplus.charge.pps.disable"          "persist.sys.oppo.charge.pps.disable"          "0"
set_prop_dual "persist.sys.oplus.charge.limit.enable"         "persist.sys.oppo.charge.limit.enable"         "0"

log_p "属性注入完成（双命名空间兼容模式）"
