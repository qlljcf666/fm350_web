#!/bin/sh
# FM350 Web CGI: GET /cgi-bin/status
# 返回 JSON 状态: 模式/拨号状态/IP/Signal/USB设备信息
# ====================================================

. /lib/functions.sh 2>/dev/null || true

MODEM_MAC="00:00:11:12:13:14"

detect_mode() {
    [ -d "/sys/class/net/ccmni0" ] && echo "pcie" && return
    ls /sys/class/net/usb* 1>/dev/null 2>&1 && echo "usb" && return
    ls /dev/ttyUSB* 1>/dev/null 2>&1 && echo "usb" && return
    echo "unknown"
}

get_ip() {
    local dev
    case "$(detect_mode)" in
        pcie) dev=$(ls /sys/class/net/ccmni*/address 2>/dev/null | head -1 | awk -F/ '{print $(NF-1)}') ;;
        usb)  dev=$(find /sys/class/net -name "usb*" -type d 2>/dev/null | head -1 | awk -F/ '{print $(NF-1)}') ;;
    esac
    [ -z "$dev" ] && { echo ""; return; }
    ip -4 addr show "$dev" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
}

get_ifaces_json() {
    local first=1
    echo "["
    for d in /sys/class/net/*; do
        local name=$(basename "$d")
        local mac=$(cat "$d/address" 2>/dev/null)
        local state=$(cat "$d/operstate" 2>/dev/null)
        local speed=$(cat "$d/speed" 2>/dev/null)
        local ip=$(ip -4 addr show "$name" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [ -z "$mac" ] && continue
        $first || echo ","
        first=0
        printf '{"name":"%s","mac":"%s","state":"%s","ip":"%s","speed":"%s"}' "$name" "$mac" "$state" "$ip" "$speed"
    done
    echo "]"
}

get_signal() {
    # 优先 MTK ATCI 服务
    if command -v fibocom_cmd >/dev/null 2>&1; then
        fibocom_cmd "" "AT%CSQ" 2>/dev/null | grep -oE '[0-9]+' | head -1 && return
        fibocom_cmd "" "AT^HCSQ?" 2>/dev/null && return
    fi
    # 直接 ttyUSB AT
    local tty=$(ls /dev/ttyUSB* 2>/dev/null | head -1)
    [ -n "$tty" ] && echo -ne "AT%CSQ\r\n" | timeout 2 microcom -t 300 "$tty" 2>/dev/null | tail -1
}

get_siminfo() {
    if command -v fibocom_cmd >/dev/null 2>&1; then
        fibocom_cmd "" "AT+CIMI" 2>/dev/null | tail -1
        fibocom_cmd "" "AT+CPIN?" 2>/dev/null | tail -1
    fi
}

get_mode() {
    if command -v fibocom_cmd >/dev/null 2>&1; then
        fibocom_cmd "" "AT%MODE?" 2>/dev/null | tail -1
    fi
}

build_json() {
    local mode=$(detect_mode)
    local ip=$(get_ip)
    local signal=$(get_signal)
    local siminfo=$(get_siminfo)
    local curmode=$(get_mode)
    local ifaces=$(get_ifaces_json)
    local state=$(cat /var/run/fm350/dial_state 2>/dev/null || echo "idle")

    cat <<JSON
{"mode":"$mode","dial_state":"$state","ip":"$ip","signal":"$signal","siminfo":"$siminfo","current_mode":"$curmode","ifaces":$ifaces}
JSON
}

# CGI header
echo "Content-Type: application/json; charset=utf-8"
echo "Cache-Control: no-store"
echo ""
build_json
