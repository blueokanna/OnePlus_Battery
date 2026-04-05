#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/local/tmp/op12_chg_fix.log

has_cmd() { command -v "$1" >/dev/null 2>&1; }

read_prop_any() {
    local k v
    for k in "$@"; do
        v=$(getprop "$k")
        if [ -n "$v" ]; then
            echo "$v"
            return
        fi
    done
    echo ""
}

read_first_value() {
    local p
    for p in "$@"; do
        if [ -f "$p" ]; then
            cat "$p" 2>/dev/null
            return
        fi
    done
    echo ""
}

abs_int() {
    local n="$1"
    if [ -z "$n" ]; then
        echo ""
        return
    fi
    if [ "$n" -lt 0 ] 2>/dev/null; then
        echo $((0 - n))
    else
        echo "$n"
    fi
}

read_screen_state() {
    local blank
    blank=$(read_first_value /sys/class/graphics/fb0/blank /sys/class/graphics/fb1/blank)
    case "$blank" in
        0)
            echo "on"
            return
            ;;
        1|4)
            echo "off"
            return
            ;;
    esac

    if has_cmd dumpsys; then
        if dumpsys power 2>/dev/null | grep -q "mWakefulness=Awake"; then
            echo "on"
        else
            echo "off"
        fi
        return
    fi

    echo "unknown"
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

apply_temp_policy() {
    BAT_TEMP=$(read_battery_temp)
    HOT_MODE=0

    if [ -n "$BAT_TEMP" ] && [ "$BAT_TEMP" -ge 430 ] 2>/dev/null; then
        HOT_MODE=1
    fi

    if [ "$HOT_MODE" -eq 1 ]; then
        PPS_DISABLE="1"
        QC_BACK="1"
    else
        PPS_DISABLE="0"
        QC_BACK="0"
    fi

    if [ "$PROFILE" = "ace" ] && [ "$HOT_MODE" -eq 0 ]; then
        QC_BACK="1"
    fi
}

get_c2c_fix_mode() {
    # 0: 关闭; 1: 智能防抖修复(默认); 2: 强修复
    local mode
    mode=$(read_prop_any \
        persist.sys.oplus.c2c.fix.mode \
        persist.sys.oppo.c2c.fix.mode \
        persist.sys.oplus.c2c.force_fix.enable \
        persist.sys.oppo.c2c.force_fix.enable)

    case "$mode" in
        0|off|OFF|false|FALSE)
            echo "0"
            ;;
        2|strong|STRONG|force|FORCE)
            echo "2"
            ;;
        *)
            echo "1"
            ;;
    esac
}

get_screenoff_guard_mode() {
    # 0: 关闭; 1: 开启(默认)
    local mode
    mode=$(read_prop_any \
        persist.sys.oplus.c2c.screenoff.guard \
        persist.sys.oppo.c2c.screenoff.guard)

    case "$mode" in
        0|off|OFF|false|FALSE)
            echo "0"
            ;;
        *)
            echo "1"
            ;;
    esac
}

get_port_policy_mode() {
    # 0: 关闭端口自适应策略(兼容旧行为); 1: 开启(默认)
    local mode
    mode=$(read_prop_any \
        persist.sys.oplus.c2c.port.policy.enable \
        persist.sys.oppo.c2c.port.policy.enable)

    case "$mode" in
        0|off|OFF|false|FALSE)
            echo "0"
            ;;
        *)
            echo "1"
            ;;
    esac
}

get_flap_guard_mode() {
    # 0: 关闭黑屏防抖守护; 1: 开启(默认)
    local mode
    mode=$(read_prop_any \
        persist.sys.oplus.c2c.flap.guard.enable \
        persist.sys.oppo.c2c.flap.guard.enable)

    case "$mode" in
        0|off|OFF|false|FALSE)
            echo "0"
            ;;
        *)
            echo "1"
            ;;
    esac
}

classify_usb_port_type() {
    local t="$1"

    case "$t" in
        *sdp*)
            echo "sdp"
            ;;
        *cdp*)
            echo "cdp"
            ;;
        *dcp*|*pd*|*qc*|*vooc*|*dash*|*warp*|*ac*|*charger*)
            echo "charger"
            ;;
        *usb*|*unknown*)
            echo "unknown_pc"
            ;;
        *)
            echo "other"
            ;;
    esac
}

get_flap_top_class() {
    local top_class="sdp"
    local top_count="$FLAP_TRIG_SDP"

    if [ "$FLAP_TRIG_CDP" -gt "$top_count" ]; then
        top_class="cdp"
        top_count="$FLAP_TRIG_CDP"
    fi
    if [ "$FLAP_TRIG_UNKNOWN_PC" -gt "$top_count" ]; then
        top_class="unknown_pc"
        top_count="$FLAP_TRIG_UNKNOWN_PC"
    fi
    if [ "$FLAP_TRIG_CHARGER" -gt "$top_count" ]; then
        top_class="charger"
        top_count="$FLAP_TRIG_CHARGER"
    fi
    if [ "$FLAP_TRIG_OTHER" -gt "$top_count" ]; then
        top_class="other"
        top_count="$FLAP_TRIG_OTHER"
    fi
    if [ "$FLAP_TRIG_LEGACY" -gt "$top_count" ]; then
        top_class="legacy"
        top_count="$FLAP_TRIG_LEGACY"
    fi

    echo "${top_class}:${top_count}"
}

record_flap_trigger() {
    local cls="$1"
    local reason="$2"
    local top_info

    FLAP_TRIG_TOTAL=$((FLAP_TRIG_TOTAL + 1))
    case "$cls" in
        sdp)
            FLAP_TRIG_SDP=$((FLAP_TRIG_SDP + 1))
            ;;
        cdp)
            FLAP_TRIG_CDP=$((FLAP_TRIG_CDP + 1))
            ;;
        unknown_pc)
            FLAP_TRIG_UNKNOWN_PC=$((FLAP_TRIG_UNKNOWN_PC + 1))
            ;;
        charger)
            FLAP_TRIG_CHARGER=$((FLAP_TRIG_CHARGER + 1))
            ;;
        other)
            FLAP_TRIG_OTHER=$((FLAP_TRIG_OTHER + 1))
            ;;
        *)
            FLAP_TRIG_LEGACY=$((FLAP_TRIG_LEGACY + 1))
            ;;
    esac

    top_info=$(get_flap_top_class)
    log_msg "[防抖统计] trigger#${FLAP_TRIG_TOTAL} reason=${reason} class=${cls} top=${top_info} sdp=${FLAP_TRIG_SDP} cdp=${FLAP_TRIG_CDP} unknown_pc=${FLAP_TRIG_UNKNOWN_PC} charger=${FLAP_TRIG_CHARGER} other=${FLAP_TRIG_OTHER} legacy=${FLAP_TRIG_LEGACY}"
}

log_flap_summary() {
    local tag="$1"
    local top_info

    [ "$FLAP_TRIG_TOTAL" -le 0 ] && return
    top_info=$(get_flap_top_class)
    log_msg "[防抖统计汇总][${tag}] total=${FLAP_TRIG_TOTAL} top=${top_info} sdp=${FLAP_TRIG_SDP} cdp=${FLAP_TRIG_CDP} unknown_pc=${FLAP_TRIG_UNKNOWN_PC} charger=${FLAP_TRIG_CHARGER} other=${FLAP_TRIG_OTHER} legacy=${FLAP_TRIG_LEGACY}"
}

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
log_msg "  OPlus 充电兼容修复 v1.1 - 启动诊断"
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

PROFILE=$(detect_profile)
BAT_TEMP=""
HOT_MODE=0

VOOCPHY=""
CHECK_USB=""

case "$PROFILE" in
    op12)
        VOOCPHY="3"
        CHECK_USB="0"
        ;;
    op12r)
        VOOCPHY="2"
        CHECK_USB="0"
        ;;
    ace)
        VOOCPHY="2"
        CHECK_USB=""
        ;;
    *)
        VOOCPHY=""
        CHECK_USB=""
        ;;
esac

apply_temp_policy

log_msg "分档  : $PROFILE"
if [ "$HOT_MODE" -eq 1 ]; then
    log_msg "温控  : 高温(${BAT_TEMP} 0.1C)，启用保守策略"
else
    log_msg "温控  : 常温(${BAT_TEMP:-unknown} 0.1C)，启用常规策略"
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

ensure_prop() {
    local name="$1" expected="$2"
    local cur
    cur=$(getprop "$name")
    if [ "$cur" != "$expected" ]; then
        resetprop "$name" "$expected"
        log_msg "[动态修复] $name: '$cur' -> '$expected'"
    fi
}

ensure_prop_dual() {
    local oplus_name="$1"
    local oppo_name="$2"
    local expected="$3"
    ensure_prop "$oplus_name" "$expected"
    ensure_prop "$oppo_name" "$expected"
}

force_sink_role_if_needed() {
    local role_node role_val fixed
    fixed=0
    for role_node in /sys/class/typec/port0/power_role /sys/class/typec/port1/power_role; do
        if [ -w "$role_node" ]; then
            role_val=$(cat "$role_node" 2>/dev/null | tr '[:upper:]' '[:lower:]')
            if [ "$role_val" = "source" ]; then
                echo sink > "$role_node" 2>/dev/null
                log_msg "[C2C修复] Type-C role: source -> sink ($role_node)"
                fixed=1
            fi
        fi
    done
    echo "$fixed"
}

recover_c2c_soft() {
    ensure_prop_dual "persist.sys.oplus.charge.pps.disable"          "persist.sys.oppo.charge.pps.disable"          "1"
    ensure_prop_dual "persist.vendor.oplus.charger.chg_vooc_qc_back" "persist.vendor.oppo.charger.chg_vooc_qc_back" "1"
    ensure_prop_dual "persist.vendor.oplus.charger.check_usb"        "persist.vendor.oppo.charger.check_usb"        "0"
}

recover_c2c_normal() {
    ensure_prop_dual "persist.sys.oplus.charge.pps.disable"          "persist.sys.oppo.charge.pps.disable"          "$PPS_DISABLE"
    ensure_prop_dual "persist.vendor.oplus.charger.chg_vooc_qc_back" "persist.vendor.oppo.charger.chg_vooc_qc_back" "$QC_BACK"
    if [ -n "$CHECK_USB" ]; then
        ensure_prop_dual "persist.vendor.oplus.charger.check_usb" "persist.vendor.oppo.charger.check_usb" "$CHECK_USB"
    fi
}

log_msg "-- 充电属性校验 --"
chk_fix_dual "persist.vendor.oplus.charger.version"          "persist.vendor.oppo.charger.version"          "2"
if [ -n "$VOOCPHY" ]; then
    chk_fix_dual "persist.vendor.oplus.charger.voocphy_support" "persist.vendor.oppo.charger.voocphy_support" "$VOOCPHY"
else
    log_msg "[跳过] voocphy_support（generic 档不强推）"
fi
chk_fix_dual "persist.sys.oplus.charge.pps.disable"          "persist.sys.oppo.charge.pps.disable"          "$PPS_DISABLE"
chk_fix_dual "persist.vendor.oplus.charger.chg_vooc_qc_back" "persist.vendor.oppo.charger.chg_vooc_qc_back" "$QC_BACK"
chk_fix_dual "persist.vendor.oplus.charger.mmi_test"         "persist.vendor.oppo.charger.mmi_test"         "0"
chk_fix_dual "persist.sys.oplus.charge.limit.enable"         "persist.sys.oppo.charge.limit.enable"         "0"
if [ -n "$CHECK_USB" ]; then
    chk_fix_dual "persist.vendor.oplus.charger.check_usb" "persist.vendor.oppo.charger.check_usb" "$CHECK_USB"
else
    log_msg "[跳过] check_usb（降低副作用）"
fi

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

log_msg "日志路径: $LOG"
log_msg "C2C监控: 已启用（8秒轮询，智能防抖 + 冷却控制）"
log_msg "C2C开关: persist.sys.oplus.c2c.fix.mode = 0(关闭) / 1(智能默认) / 2(强修复)"
log_msg "锁屏守护: persist.sys.oplus.c2c.screenoff.guard = 0(关闭) / 1(开启默认)"
log_msg "端口策略: persist.sys.oplus.c2c.port.policy.enable = 0(旧行为) / 1(按SDP/CDP自适应,默认)"
log_msg "黑屏防抖: persist.sys.oplus.c2c.flap.guard.enable = 0(关闭) / 1(开启默认)"
log_msg "防抖统计: 已启用（记录黑屏保护态触发次数与端口类型命中）"

LAST_C2C_STATE="init"
LAST_USB_ONLINE=""
LAST_SCREEN_STATE="unknown"
LAST_PORT_CLASS="init"
BAD_STREAK=0
SESSION_ID=0
LAST_SESSION_TS=0
SESSION_CHURN_COUNT=0
FLAP_GUARD_UNTIL=0
FLAP_TRIG_TOTAL=0
FLAP_TRIG_SDP=0
FLAP_TRIG_CDP=0
FLAP_TRIG_UNKNOWN_PC=0
FLAP_TRIG_CHARGER=0
FLAP_TRIG_OTHER=0
FLAP_TRIG_LEGACY=0
LAST_STATS_REPORT_TS=0
HARD_ACTIONS_IN_SESSION=0
LAST_HARD_ACTION_TS=0
LAST_SOFT_ACTION_TS=0

# 策略参数（避免反复触发“重新拔插”提示）
POLL_INTERVAL=8
SOFT_TRIGGER_STREAK=3
SOFT_COOLDOWN_SEC=45
HARD_COOLDOWN_SEC=180
HARD_MAX_PER_SESSION=1
SMART_HARD_STREAK=8
SCREENOFF_SOFT_TRIGGER_STREAK=6
SCREENOFF_SOFT_COOLDOWN_SEC=180
SESSION_CHURN_WINDOW_SEC=180
SESSION_CHURN_THRESHOLD=4
FLAP_GUARD_HOLD_SEC=300
FLAP_GUARD_SOFT_COOLDOWN_SEC=300
STATS_REPORT_INTERVAL_SEC=600

while true; do
    apply_temp_policy
    C2C_FIX_MODE=$(get_c2c_fix_mode)
    SCREENOFF_GUARD_MODE=$(get_screenoff_guard_mode)
    PORT_POLICY_MODE=$(get_port_policy_mode)
    FLAP_GUARD_MODE=$(get_flap_guard_mode)

    USB_ONLINE=$(read_first_value /sys/class/power_supply/usb/online /sys/class/power_supply/pc_port/online)
    [ -z "$USB_ONLINE" ] && USB_ONLINE="0"
    USB_TYPE=$(read_first_value /sys/class/power_supply/usb/real_type /sys/class/power_supply/usb/type)
    USB_ROLE=$(read_first_value /sys/class/typec/port0/power_role /sys/class/typec/port1/power_role)
    BAT_STATUS=$(read_first_value /sys/class/power_supply/battery/status)
    BAT_CURRENT_NOW=$(read_first_value /sys/class/power_supply/battery/current_now)
    USB_CURRENT_NOW=$(read_first_value /sys/class/power_supply/usb/current_now /sys/class/power_supply/usb/input_current_now /sys/class/power_supply/pc_port/current_now /sys/class/power_supply/pc_port/input_current_now)
    SCREEN_STATE=$(read_screen_state)
    NOW_TS=$(date +%s)

    USB_TYPE_L=$(echo "$USB_TYPE" | tr '[:upper:]' '[:lower:]')
    USB_ROLE_L=$(echo "$USB_ROLE" | tr '[:upper:]' '[:lower:]')
    BAT_STATUS_L=$(echo "$BAT_STATUS" | tr '[:upper:]' '[:lower:]')
    BAT_CURRENT_NOW_CLEAN=$(echo "$BAT_CURRENT_NOW" | tr -cd '0-9-')
    USB_CURRENT_NOW_CLEAN=$(echo "$USB_CURRENT_NOW" | tr -cd '0-9-')
    BAT_CURRENT_ABS=$(abs_int "$BAT_CURRENT_NOW_CLEAN")
    USB_CURRENT_ABS=$(abs_int "$USB_CURRENT_NOW_CLEAN")

    PORT_CLASS="legacy"
    if [ "$PORT_POLICY_MODE" = "1" ]; then
        PORT_CLASS=$(classify_usb_port_type "$USB_TYPE_L")
    fi
    if [ "$PORT_CLASS" != "$LAST_PORT_CLASS" ]; then
        log_msg "[端口策略] mode=${PORT_POLICY_MODE}, type=${USB_TYPE:-unknown}, class=${PORT_CLASS}"
        LAST_PORT_CLASS="$PORT_CLASS"
    fi

    if [ "$SCREEN_STATE" != "$LAST_SCREEN_STATE" ]; then
        BAD_STREAK=0
        log_msg "[屏幕状态] ${LAST_SCREEN_STATE} -> ${SCREEN_STATE}"
        LAST_SCREEN_STATE="$SCREEN_STATE"
    fi

    if [ "$USB_ONLINE" = "1" ] && [ "$LAST_USB_ONLINE" != "1" ]; then
        SESSION_ID=$((SESSION_ID + 1))
        HARD_ACTIONS_IN_SESSION=0
        BAD_STREAK=0
        log_msg "[C2C会话] 新会话 #$SESSION_ID"

        if [ "$LAST_SESSION_TS" -gt 0 ] && [ $((NOW_TS - LAST_SESSION_TS)) -le "$SESSION_CHURN_WINDOW_SEC" ]; then
            SESSION_CHURN_COUNT=$((SESSION_CHURN_COUNT + 1))
        else
            SESSION_CHURN_COUNT=1
        fi
        LAST_SESSION_TS=$NOW_TS

        if [ "$FLAP_GUARD_MODE" = "1" ] && [ "$SCREEN_STATE" != "on" ] && [ "$SESSION_CHURN_COUNT" -ge "$SESSION_CHURN_THRESHOLD" ]; then
            FLAP_GUARD_UNTIL=$((NOW_TS + FLAP_GUARD_HOLD_SEC))
            BAD_STREAK=0
            record_flap_trigger "$PORT_CLASS" "session_churn"
            log_msg "[防抖守护] 检测到黑屏短时多次重连(churn=$SESSION_CHURN_COUNT)，进入稳定充电保护态 ${FLAP_GUARD_HOLD_SEC}s"
        fi
    elif [ "$USB_ONLINE" != "1" ] && [ "$LAST_USB_ONLINE" = "1" ]; then
        BAD_STREAK=0
        HARD_ACTIONS_IN_SESSION=0
        if [ "$LAST_C2C_STATE" != "init" ]; then
            log_msg "[C2C会话] 连接已断开"
        fi
    fi
    LAST_USB_ONLINE="$USB_ONLINE"

    C2C_PC_LINK=0
    if [ "$PORT_POLICY_MODE" = "1" ]; then
        case "$PORT_CLASS" in
            sdp|cdp|unknown_pc)
                [ "$USB_ONLINE" = "1" ] && C2C_PC_LINK=1
                ;;
            *)
                C2C_PC_LINK=0
                ;;
        esac
    else
        if [ "$USB_ONLINE" = "1" ] && echo "$USB_TYPE_L" | grep -qiE "usb|sdp|cdp|unknown"; then
            C2C_PC_LINK=1
        fi
    fi

    # 默认阈值（旧行为）
    SOFT_TRIGGER_DYNAMIC=$SOFT_TRIGGER_STREAK
    SOFT_COOLDOWN_DYNAMIC=$SOFT_COOLDOWN_SEC
    SMART_HARD_DYNAMIC=$SMART_HARD_STREAK
    SCREENOFF_SOFT_TRIGGER_DYNAMIC=$SCREENOFF_SOFT_TRIGGER_STREAK
    SCREENOFF_SOFT_COOLDOWN_DYNAMIC=$SCREENOFF_SOFT_COOLDOWN_SEC
    ALLOW_HARD_NORMAL=1
    ALLOW_HARD_SCREENOFF=1

    if [ "$PORT_POLICY_MODE" = "1" ]; then
        case "$PORT_CLASS" in
            sdp)
                SOFT_TRIGGER_DYNAMIC=4
                SOFT_COOLDOWN_DYNAMIC=90
                SMART_HARD_DYNAMIC=9999
                SCREENOFF_SOFT_TRIGGER_DYNAMIC=7
                SCREENOFF_SOFT_COOLDOWN_DYNAMIC=240
                ALLOW_HARD_NORMAL=0
                ALLOW_HARD_SCREENOFF=0
                ;;
            cdp)
                SOFT_TRIGGER_DYNAMIC=3
                SOFT_COOLDOWN_DYNAMIC=60
                SMART_HARD_DYNAMIC=10
                SCREENOFF_SOFT_TRIGGER_DYNAMIC=6
                SCREENOFF_SOFT_COOLDOWN_DYNAMIC=180
                ALLOW_HARD_NORMAL=1
                ALLOW_HARD_SCREENOFF=0
                ;;
            unknown_pc)
                SOFT_TRIGGER_DYNAMIC=5
                SOFT_COOLDOWN_DYNAMIC=120
                SMART_HARD_DYNAMIC=9999
                SCREENOFF_SOFT_TRIGGER_DYNAMIC=8
                SCREENOFF_SOFT_COOLDOWN_DYNAMIC=300
                ALLOW_HARD_NORMAL=0
                ALLOW_HARD_SCREENOFF=0
                ;;
            *)
                ;;
        esac
    fi

    EFFECTIVE_CHARGING=0
    if echo "$BAT_STATUS_L" | grep -qiE "charging|full"; then
        EFFECTIVE_CHARGING=1
    elif [ -n "$USB_CURRENT_ABS" ] && [ "$USB_CURRENT_ABS" -gt 20000 ] 2>/dev/null; then
        # 优先使用 USB 输入电流判断，降低仅看 battery/status 的误判
        EFFECTIVE_CHARGING=1
    elif [ -n "$BAT_CURRENT_ABS" ] && [ "$BAT_CURRENT_ABS" -gt 300000 ] 2>/dev/null; then
        # 兜底：部分机型无 USB 电流节点时，用较高阈值判定有效输入
        EFFECTIVE_CHARGING=1
    fi

    SCREEN_GUARD_ACTIVE=0
    if [ "$SCREENOFF_GUARD_MODE" = "1" ] && [ "$C2C_PC_LINK" -eq 1 ] && [ "$SCREEN_STATE" != "on" ]; then
        SCREEN_GUARD_ACTIVE=1
    fi

    FLAP_GUARD_ACTIVE=0
    if [ "$FLAP_GUARD_MODE" = "1" ] && [ "$SCREEN_GUARD_ACTIVE" -eq 1 ] && [ "$FLAP_GUARD_UNTIL" -gt "$NOW_TS" ]; then
        FLAP_GUARD_ACTIVE=1
    fi

    C2C_NEED_RECOVERY=0
    if [ "$C2C_PC_LINK" -eq 1 ] && [ "$EFFECTIVE_CHARGING" -ne 1 ]; then
        C2C_NEED_RECOVERY=1
    fi
    if [ "$C2C_PC_LINK" -eq 1 ] && [ "$USB_ROLE_L" = "source" ] && [ "$SCREEN_GUARD_ACTIVE" -eq 0 ]; then
        C2C_NEED_RECOVERY=1
    fi

    if [ "$C2C_NEED_RECOVERY" -eq 1 ]; then
        BAD_STREAK=$((BAD_STREAK + 1))
    else
        BAD_STREAK=0
    fi

    if [ "$C2C_FIX_MODE" = "0" ]; then
        CUR_C2C_STATE="disabled"
        recover_c2c_normal
    elif [ "$FLAP_GUARD_ACTIVE" -eq 1 ]; then
        CUR_C2C_STATE="flap_guard"

        # 保护态中仅低频软修复，避免频繁动作导致反复跳连
        if [ "$C2C_NEED_RECOVERY" -eq 1 ] && [ $((NOW_TS - LAST_SOFT_ACTION_TS)) -ge "$FLAP_GUARD_SOFT_COOLDOWN_SEC" ]; then
            recover_c2c_soft
            LAST_SOFT_ACTION_TS=$NOW_TS
            log_msg "[防抖守护] 保护态低频软修复: type=${USB_TYPE:-unknown}, battery=${BAT_STATUS:-unknown}, usb_current=${USB_CURRENT_NOW:-unknown}, current_now=${BAT_CURRENT_NOW:-unknown}"
        fi

        # 保护态禁止强动作
    elif [ "$C2C_NEED_RECOVERY" -eq 1 ]; then
        CUR_C2C_STATE="recovery"

        if [ "$SCREEN_GUARD_ACTIVE" -eq 1 ]; then
            if [ "$BAD_STREAK" -ge "$SCREENOFF_SOFT_TRIGGER_DYNAMIC" ] && [ $((NOW_TS - LAST_SOFT_ACTION_TS)) -ge "$SCREENOFF_SOFT_COOLDOWN_DYNAMIC" ]; then
                recover_c2c_soft
                LAST_SOFT_ACTION_TS=$NOW_TS
                log_msg "[C2C修复][锁屏守护] 软修复已执行: streak=$BAD_STREAK, type=${USB_TYPE:-unknown}, battery=${BAT_STATUS:-unknown}, usb_current=${USB_CURRENT_NOW:-unknown}, current_now=${BAT_CURRENT_NOW:-unknown}"
            fi

            if [ "$C2C_FIX_MODE" = "2" ] \
                && [ "$ALLOW_HARD_SCREENOFF" -eq 1 ] \
                && [ "$BAD_STREAK" -ge "$SCREENOFF_SOFT_TRIGGER_DYNAMIC" ] \
                && [ "$HARD_ACTIONS_IN_SESSION" -lt "$HARD_MAX_PER_SESSION" ] \
                && [ $((NOW_TS - LAST_HARD_ACTION_TS)) -ge "$HARD_COOLDOWN_SEC" ]; then
                ROLE_FIXED=$(force_sink_role_if_needed)
                if [ "$ROLE_FIXED" = "1" ]; then
                    HARD_ACTIONS_IN_SESSION=$((HARD_ACTIONS_IN_SESSION + 1))
                    LAST_HARD_ACTION_TS=$NOW_TS
                    log_msg "[C2C修复][锁屏守护] 强修复已执行(单会话限1次): role切换成功"
                fi
            fi
        else
            if [ "$BAD_STREAK" -ge "$SOFT_TRIGGER_DYNAMIC" ] && [ $((NOW_TS - LAST_SOFT_ACTION_TS)) -ge "$SOFT_COOLDOWN_DYNAMIC" ]; then
                recover_c2c_soft
                LAST_SOFT_ACTION_TS=$NOW_TS
                log_msg "[C2C修复] 软修复已执行: streak=$BAD_STREAK, type=${USB_TYPE:-unknown}, role=${USB_ROLE:-unknown}, battery=${BAT_STATUS:-unknown}, usb_current=${USB_CURRENT_NOW:-unknown}"
            fi

            DO_HARD=0
            if [ "$C2C_FIX_MODE" = "2" ] && [ "$ALLOW_HARD_NORMAL" -eq 1 ] && [ "$BAD_STREAK" -ge "$SOFT_TRIGGER_DYNAMIC" ]; then
                DO_HARD=1
            elif [ "$C2C_FIX_MODE" = "1" ] && [ "$ALLOW_HARD_NORMAL" -eq 1 ] && [ "$BAD_STREAK" -ge "$SMART_HARD_DYNAMIC" ]; then
                # 智能模式下仅在长时间故障后触发一次强动作
                DO_HARD=1
            fi

            if [ "$DO_HARD" -eq 1 ] \
                && [ "$HARD_ACTIONS_IN_SESSION" -lt "$HARD_MAX_PER_SESSION" ] \
                && [ $((NOW_TS - LAST_HARD_ACTION_TS)) -ge "$HARD_COOLDOWN_SEC" ]; then
                ROLE_FIXED=$(force_sink_role_if_needed)
                if [ "$ROLE_FIXED" = "1" ]; then
                    HARD_ACTIONS_IN_SESSION=$((HARD_ACTIONS_IN_SESSION + 1))
                    LAST_HARD_ACTION_TS=$NOW_TS
                    log_msg "[C2C修复] 强修复已执行: role切换成功, session_actions=$HARD_ACTIONS_IN_SESSION"
                fi
            fi
        fi
    else
        CUR_C2C_STATE="normal"
        recover_c2c_normal
    fi

    if [ "$CUR_C2C_STATE" != "$LAST_C2C_STATE" ]; then
        if [ "$CUR_C2C_STATE" = "recovery" ]; then
            log_msg "[C2C状态] 进入恢复模式: online=${USB_ONLINE:-0}, type=${USB_TYPE:-unknown}, role=${USB_ROLE:-unknown}, battery=${BAT_STATUS:-unknown}, usb_current=${USB_CURRENT_NOW:-unknown}, current_now=${BAT_CURRENT_NOW:-unknown}, screen=${SCREEN_STATE:-unknown}, temp=${BAT_TEMP:-unknown}"
        elif [ "$CUR_C2C_STATE" = "flap_guard" ]; then
            log_msg "[C2C状态] 进入防抖守护态: online=${USB_ONLINE:-0}, type=${USB_TYPE:-unknown}, role=${USB_ROLE:-unknown}, battery=${BAT_STATUS:-unknown}, usb_current=${USB_CURRENT_NOW:-unknown}, screen=${SCREEN_STATE:-unknown}, guard_left=$((FLAP_GUARD_UNTIL - NOW_TS))s"
        elif [ "$CUR_C2C_STATE" = "disabled" ]; then
            log_msg "[C2C状态] C2C修复已关闭（mode=0）"
        else
            log_msg "[C2C状态] 返回常规模式: online=${USB_ONLINE:-0}, type=${USB_TYPE:-unknown}, role=${USB_ROLE:-unknown}, battery=${BAT_STATUS:-unknown}, usb_current=${USB_CURRENT_NOW:-unknown}, current_now=${BAT_CURRENT_NOW:-unknown}, screen=${SCREEN_STATE:-unknown}, temp=${BAT_TEMP:-unknown}"
        fi
        LAST_C2C_STATE="$CUR_C2C_STATE"
    fi

    if [ "$FLAP_TRIG_TOTAL" -gt 0 ] && [ $((NOW_TS - LAST_STATS_REPORT_TS)) -ge "$STATS_REPORT_INTERVAL_SEC" ]; then
        log_flap_summary "periodic"
        LAST_STATS_REPORT_TS=$NOW_TS
    fi

    sleep "$POLL_INTERVAL"
done
