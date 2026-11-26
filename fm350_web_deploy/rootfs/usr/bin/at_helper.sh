#!/bin/sh
# AT 命令通用辅助库 —— 统一入口, 被 SMS / 锁频 / 拨号脚本共同引用
# 依赖: 优先 fibocom_cmd (FM350 自带), 其次 microcom, 最后 gcom
# 使用: . /usr/bin/at_helper.sh
# ================================================================

# ---- 自动探测 AT 工具和端口 ----
AT_PORT_CACHE="/var/run/fm350/at_port"

at_find_tool() {
    # 按优先级返回工具名
    if [ -x /usr/bin/fibocom_cmd ] || command -v fibocom_cmd >/dev/null 2>&1; then
        echo "fibocom"
    elif command -v microcom >/dev/null 2>&1; then
        echo "microcom"
    elif command -v gcom >/dev/null 2>&1; then
        echo "gcom"
    else
        echo "none"
    fi
}

at_find_port() {
    # 返回可用的 AT 命令端口 (ttyUSBx)
    [ -f "$AT_PORT_CACHE" ] && [ -e "$(cat $AT_PORT_CACHE)" ] && { cat "$AT_PORT_CACHE"; return; }

    local tool=$(at_find_tool)
    for t in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3 /dev/ttyUSB4 /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2; do
        [ -e "$t" ] || continue
        # 发 AT 看 OK
        case "$tool" in
            fibocom)  fibocom_cmd "" "AT" 2>/dev/null | grep -qi "OK" && { echo "$t" > "$AT_PORT_CACHE"; echo "$t"; return; } ;;
            microcom) echo -ne "AT\r\n" | timeout 2 microcom -t 200 "$t" 2>/dev/null | grep -qi "OK" && { echo "$t" > "$AT_PORT_CACHE"; echo "$t"; return; } ;;
            gcom)     echo "AT" | gcom -d "$t" 2>/dev/null | grep -qi "OK" && { echo "$t" > "$AT_PORT_CACHE"; echo "$t"; return; } ;;
        esac
    done
    # 兜底
    ls /dev/ttyUSB* 2>/dev/null | head -1
}

at_reset_port_cache() {
    rm -f "$AT_PORT_CACHE"
}

# ---- 发一条 AT 命令, 返回 stdout ----
# 用法: at_cmd "AT+CMEE=2" [timeout_ms]
at_cmd() {
    local cmd="$1"
    local timeout="${2:-3000}"
    local port=$(at_find_port)
    local tool=$(at_find_tool)

    [ -z "$port" ] && { echo "NO_AT_PORT"; return 1; }

    case "$tool" in
        fibocom)
            fibocom_cmd "" "$cmd" 2>/dev/null
            ;;
        microcom)
            echo -ne "${cmd}\r\n" | timeout $((timeout/1000)) microcom -t "$timeout" "$port" 2>/dev/null
            ;;
        gcom)
            # gcom 是脚本式, 对单条 AT 直接 echo 管道
            echo "$cmd" | gcom -d "$port" 2>/dev/null
            ;;
        *)
            echo "NO_AT_TOOL: need fibocom_cmd/microcom/gcom"
            return 1
            ;;
    esac
}

# ---- 发命令并判断 OK ----
at_ok() {
    local out=$(at_cmd "$1" "${2:-3000}")
    echo "$out" | grep -qi "OK"
}

# ---- 清理返回字符串 (去 \r, \000, 尾部空白) ----
at_clean() {
    tr -d '\r\000' | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//'
}

# ---- 获取 SIM 状态 ----
at_get_sim_state() {
    local out=$(at_cmd "AT+CPIN?" | at_clean)
    # +CPIN: READY / SIM PIN / PUK
    echo "$out"
}

# ---- 获取运营商 ----
at_get_operator() {
    local out=$(at_cmd "AT+COPS?")
    # +COPS: 0,0,"中国移动",7
    echo "$out" | sed -n 's/.*"\([^"]*\)".*/\1/p' | head -1
}

# ---- 获取信号强度 CSQ (0-31) ----
at_get_csq() {
    local out=$(at_cmd "AT+CSQ")
    # +CSQ: 18,99
    echo "$out" | sed -n 's/.*+CSQ: *\([0-9]*\),.*/\1/p' | head -1
}

# ---- 获取网络类型 ----
at_get_net_type() {
    local out=$(at_cmd "AT%HCSQ?")
    # +HCSQ: "NR5G", 2408, 1, 5000, 10, -85, -12, -10, 16
    echo "$out" | sed -n 's/.*"+HCSQ: *\([^"]*\)".*/\1/p; s/.*%HCSQ: *\([^"]*\).*/\1/p' | head -1
}

# ---- 通用 JSON 转义 (CGI 输出安全) ----
json_escape() {
    # 读 stdin, 输出 JSON-safe 字符串
    sed -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g' \
        -e 's/\t/\\t/g' \
        -e 's/\r/\\r/g' \
        -e 's/\n/\\n/g'
}
