#!/system/bin/sh
# service.sh - late_start service 模式
# 系统完全启动后执行：二次校验属性 + 充电硬件诊断

MODDIR=${0%/*}
LOG=/data/local/tmp/op12_chg_fix.log

has_cmd() { command -v "$1" >/dev/null 2>&1; }

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 5

log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# 日志轮转（超过512KB截断）
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 524288 ]; then
    tail -n 200 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

log_msg "======================================"
log_msg "  OPlus 充电兼容修复 v1.3 - 启动诊断"
log_msg "======================================"
log_msg "型号  : $(getprop ro.product.model) ($(getprop ro.product.device))"
log_msg "系统  : $(getprop ro.build.display.id)"
log_msg "Magisk: $(magisk -v 2>/dev/null || echo N/A)"
log_msg "区域  : $(getprop ro.oplus.regionmark)"

BRAND=$(getprop ro.product.brand | tr '[:upper:]' '[:lower:]')
MANUFACTURER=$(getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')

if ! echo "$BRAND $MANUFACTURER" | grep -qE "oneplus|oppo|realme|oplus"; then
    log_msg "非 OPlus 生态设备，退出防误注入"
    exit 0
fi

if ! has_cmd resetprop; then
    log_msg "resetprop 不可用，无法执行属性修复"
    exit 0
fi

# ── 属性校验和二次修复 ────────────────────────────────────────
PROPS_FIXED=0

chk_fix() {
    local name="$1" expected="$2"
    local cur
    cur=$(getprop "$name")
    if [ "$cur" != "$expected" ]; then
        resetprop "$name" "$expected"
        log_msg "[修复] $name: '$cur' -> '$expected'"
        PROPS_FIXED=$((PROPS_FIXED + 1))
    else
        log_msg "[OK  ] $name = $cur"
    fi
}

chk_fix_dual() {
    local oplus_name="$1"
    local oppo_name="$2"
    local expected="$3"
    chk_fix "$oplus_name" "$expected"
    chk_fix "$oppo_name" "$expected"
}

log_msg "-- 充电属性校验 --"
chk_fix_dual "persist.vendor.oplus.charger.version"          "persist.vendor.oppo.charger.version"          "2"
chk_fix_dual "persist.vendor.oplus.charger.voocphy_support"  "persist.vendor.oppo.charger.voocphy_support"  "3"
chk_fix_dual "persist.sys.oplus.charge.pps.disable"          "persist.sys.oppo.charge.pps.disable"          "0"
chk_fix_dual "persist.vendor.oplus.charger.chg_vooc_qc_back" "persist.vendor.oppo.charger.chg_vooc_qc_back" "0"
chk_fix_dual "persist.vendor.oplus.charger.mmi_test"         "persist.vendor.oppo.charger.mmi_test"         "0"
chk_fix_dual "persist.sys.oplus.charge.limit.enable"         "persist.sys.oppo.charge.limit.enable"         "0"
chk_fix_dual "persist.vendor.oplus.charger.check_usb"        "persist.vendor.oppo.charger.check_usb"        "0"

if [ "$PROPS_FIXED" -eq 0 ]; then
    log_msg "✓ 所有充电属性正常，无需修复"
else
    log_msg "✓ 共修复 $PROPS_FIXED 个异常属性"
fi

# ── 硬件状态诊断 ─────────────────────────────────────────────
log_msg "-- 充电硬件诊断 --"

rnode() {
    local p="$1" lbl="$2"
    [ -f "$p" ] && log_msg "$lbl: $(cat "$p" 2>/dev/null)" || log_msg "$lbl: 节点不存在"
}

rnode_first() {
    local lbl="$1"
    shift
    local p
    for p in "$@"; do
        if [ -f "$p" ]; then
            log_msg "$lbl: $(cat "$p" 2>/dev/null) (from $p)"
            return
        fi
    done
    log_msg "$lbl: 节点不存在"
}

rnode /sys/class/power_supply/battery/status              "电池状态"
rnode /sys/class/power_supply/battery/capacity            "电量%"
rnode /sys/class/power_supply/battery/current_now         "电流(uA)"
rnode /sys/class/power_supply/battery/voltage_now         "电压(uV)"
rnode /sys/class/power_supply/battery/temp                "温度(0.1C)"
rnode_first "USB在线" /sys/class/power_supply/usb/online /sys/class/power_supply/pc_port/online
rnode_first "USB实际类型" /sys/class/power_supply/usb/real_type /sys/class/power_supply/usb/type
rnode_first "VOOC快充类型" /sys/class/oplus_chg/battery/voocphy_fast_chg_type /sys/class/oppo_chg/battery/voocphy_fast_chg_type
rnode_first "快充类型" /sys/class/oplus_chg/battery/fast_chg_type /sys/class/oppo_chg/battery/fast_chg_type
rnode_first "充电协议" /sys/class/oplus_chg/battery/charge_technology /sys/class/oppo_chg/battery/charge_technology

USB_ONLINE=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
BAT_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)

if [ "$USB_ONLINE" = "1" ] && ! echo "$BAT_STATUS" | grep -qiE "Charging|Full"; then
    log_msg "[提示] 已接入电源但电池状态非 Charging/Full，可检查线材/头或温控策略"
fi

pgrep oplus_chg_daemon > /dev/null 2>&1     && log_msg "充电守护进程: 运行中 ✓"     || log_msg "充电守护进程: 未检测到（可能已集成）"

log_msg "======================================"
log_msg "日志路径: $LOG"
log_msg "======================================"
