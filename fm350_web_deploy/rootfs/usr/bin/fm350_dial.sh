#!/bin/sh
# FM350 自动拨号 + 断网重拨守护 + 定时重启守护
# 同时支持 USB (RNDIS/ECM) 和 PCIe (CCCMNI) 两种模式
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/at_helper.sh"

LOG_FILE="/var/log/fm350_dial.log"
STATE_FILE="/var/run/fm350/dial_state"
LAST_PING_FILE="/var/run/fm350/last_ping_ok"
LOCK_FAIL_FILE="/var/run/fm350/lock_fail_count"
APN="${FM350_APN:-internet}"
PDP="${FM350_PDP:-IP}"
DIAL_PORT="${FM350_PORT:-}"
MODEM_MAC="00:00:11:12:13:14"

# 策略参数
POLL_INTERVAL=10           # 健康检查间隔 (秒)
DIAL_TIMEOUT=60            # 首次拨号最长等待 (秒)
MAX_FAIL_BEFORE_REBOOT=15  # 连续失败多少次触发 reboot

log()     { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
save_s()  { echo "$1" > "$STATE_FILE"; }
get_s()   { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "unknown"; }

# ---------- 模式检测 ----------
detect_mode() {
    if [ -d "/sys/class/net/ccmni0" ] || [ -d "/sys/class/net/wwan0" ]; then
        echo "pcie"; return
    fi
    if ls /sys/class/net/usb* 1>/dev/null 2>&1; then echo "usb"; return; fi
    if ls /dev/ttyUSB* 1>/dev/null 2>&1; then echo "usb"; return; fi
    echo "unknown"
}

find_rndis_iface() {
    for d in usb0 usb1 eth1 eth2; do
        [ -d "/sys/class/net/$d" ] || continue
        local h=$(cat /sys/class/net/$d/address 2>/dev/null)
        [ "$h" = "$MODEM_MAC" ] && { echo "$d"; return; }
    done
    ls /sys/class/net/usb* 2>/dev/null | xargs -I {} basename {} | head -1
}

# ---------- USB 模式: AT 拨号 ----------
dial_usb() {
    local port=$(at_find_port)
    [ -z "$port" ] && { log "no AT port"; return 1; }
    log "[USB] dial port=$port APN=$APN"
    save_s "usb_dialing"

    # 关旧的 PDP
    at_cmd "AT+CGACT=0,1" 2>/dev/null
    sleep 0.5

    # 设 PDP context
    at_ok "AT+CGPIAF=1,0,0,0" 1>/dev/null
    at_cmd "AT+CGDCONT=3,\"$PDP\",\"$APN\"" 3000 | at_clean

    # 激活
    local act_out=$(at_cmd "AT+CGACT=1,3" 5000 | at_clean)
    echo "$act_out" | grep -qi "OK" || { log "CGACT failed: $act_out"; save_s "usb_failed"; return 1; }

    # 取 IP
    local tries=0
    local ip=""
    while [ $tries -lt 6 ]; do
        sleep 1
        local data=$(at_cmd "AT+CGPADDR=3" 3000)
        ip=$(echo "$data" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        [ -n "$ip" ] && echo "$ip" | grep -qv "0.0.0.0" && break
        tries=$((tries+1))
    done

    [ -z "$ip" ] && { log "no IP from modem"; save_s "usb_no_ip"; return 1; }

    local ifname=$(find_rndis_iface)
    [ -z "$ifname" ] && { log "no RNDIS/ECM iface"; return 1; }

    # 配 IP (RNDIS 侧常见网关 10.64.64.1)
    local gw="10.64.64.1"
    ifconfig "$ifname" up 10.64.64.64 netmask 255.255.255.0 2>/dev/null || {
        ip link set "$ifname" up
        ip addr flush dev "$ifname"
        ip addr add 10.64.64.64/24 dev "$ifname"
    }
    ip route del default via "$gw" 2>/dev/null
    ip route add default via "$gw" 2>/dev/null

    # DNS
    local dns=$(at_cmd "AT+GTDNS=3" 3000 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
    [ -n "$dns" ] && echo "nameserver $dns" > /tmp/resolv.conf.fm350
    [ -f /tmp/resolv.conf.fm350 ] && cp /tmp/resolv.conf.fm350 /etc/resolv.conf 2>/dev/null

    log "[USB] dial OK ip=$ip iface=$ifname"
    save_s "connected usb ip=$ip"
    echo "OK" > "$LAST_PING_FILE"
    return 0
}

# ---------- PCIe 模式: 等 IP ----------
dial_pcie() {
    local dev=""
    for d in ccmni0 ccmni1 wwan0; do
        [ -d "/sys/class/net/$d" ] && { dev="$d"; break; }
    done
    [ -z "$dev" ] && { log "no pcie netdev"; return 1; }

    local tries=0
    while [ $tries -lt 30 ]; do
        local ip=$(ip -4 addr show "$dev" 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '255\.' | head -1)
        if [ -n "$ip" ] && echo "$ip" | grep -qv "127.0.0"; then
            log "[PCIe] dial OK ip=$ip dev=$dev"
            save_s "connected pcie ip=$ip dev=$dev"
            echo "OK" > "$LAST_PING_FILE"
            return 0
        fi
        tries=$((tries+1)); sleep 2
    done
    log "[PCIe] timeout on $dev"; save_s "pcie_timeout"; return 1
}

# ---------- 健康检查: 真实 ping ----------
health_check() {
    # 目标: 优先运营商 DNS (223.5.5.5), 失败兜底 8.8.8.8
    local targets="223.5.5.5 119.29.29.29 8.8.8.8"
    local mode=$(detect_mode)

    for t in $targets; do
        local dev=""
        case "$mode" in
            pcie) dev=$(ls /sys/class/net/ccmni*/address 2>/dev/null | head -1 | awk -F/ '{print $(NF-1)}') ;;
            usb)  dev=$(find_rndis_iface) ;;
        esac
        if [ -n "$dev" ]; then
            ping -c 1 -W 3 -I "$dev" "$t" >/dev/null 2>&1 && { echo "OK"; return 0; }
        fi
        ping -c 1 -W 3 "$t" >/dev/null 2>&1 && { echo "OK"; return 0; }
    done
    return 1
}

# ---------- 重拨流程 ----------
redial() {
    log "=== RE-DIAL ==="
    save_s "retrying"

    # 1) 软重启 modem 会话
    at_cmd "AT+CGACT=0" 2>/dev/null
    sleep 1

    # 2) 关闭网口
    local mode=$(detect_mode)
    case "$mode" in
        usb)
            local iface=$(find_rndis_iface)
            [ -n "$iface" ] && ifconfig "$iface" down 2>/dev/null
            ;;
        pcie)
            local dev=$(ls /sys/class/net/ccmni*/address 2>/dev/null | head -1 | awk -F/ '{print $(NF-1)}')
            [ -n "$dev" ] && ifconfig "$dev" down 2>/dev/null
            ;;
    esac
    sleep 2

    # 3) 重拨
    case "$mode" in
        usb)  dial_usb ;;
        pcie) dial_pcie ;;
        *)    log "no modem yet"; return 1 ;;
    esac
}

# ---------- 连续失败处理 ----------
handle_continuous_fail() {
    local count=$(( $(cat "$LOCK_FAIL_FILE" 2>/dev/null || echo "0") + 1 ))
    echo "$count" > "$LOCK_FAIL_FILE"

    if [ "$count" -ge "$MAX_FAIL_BEFORE_REBOOT" ]; then
        log "连续 ${count} 次重拨失败, 超过阈值 $MAX_FAIL_BEFORE_REBOOT, 30s 后 reboot"
        save_s "boot_after_retry_fail"
        (sleep 30; reboot) &
        return 2   # tell main loop to exit
    fi

    # 每 5 次失败, 软重启 modem (AT%MODE 切换一下)
    if [ $(( count % 5 )) -eq 0 ]; then
        log "每 5 次失败, 触发 AT 重启 modem"
        at_cmd "AT%REBOOT=1" 2>/dev/null   # FM350 私有 AT, 不一定所有固件都支持
        sleep 5
    fi
    return 0
}

reset_fail_count() { echo "0" > "$LOCK_FAIL_FILE"; }

# ---------- 主循环 ----------
main() {
    log "fm350_dial start, mode=$(detect_mode), APN=$APN"

    # 首次拨号
    local mode=$(detect_mode)
    case "$mode" in
        usb)  dial_usb ;;
        pcie) dial_pcie ;;
        *)
            log "wait for modem ..."
            for i in $(seq 1 20); do
                sleep 3
                mode=$(detect_mode)
                case "$mode" in
                    usb)  dial_usb && break ;;
                    pcie) dial_pcie && break ;;
                esac
                log "still waiting ... ($i/20)"
            done
            ;;
    esac

    # 健康循环
    while :; do
        if health_check; then
            # 健康
            echo "OK" > "$LAST_PING_FILE"
            reset_fail_count
            sleep "$POLL_INTERVAL"
        else
            log "health_check FAIL at $(get_s)"

            # 第一次 ping 失败: 先查接口 IP 还在不在
            local mode=$(detect_mode)
            local has_ip=0
            case "$mode" in
                usb)
                    local iface=$(find_rndis_iface)
                    [ -n "$iface" ] && ip -4 addr show "$iface" 2>/dev/null | grep -q "inet " && has_ip=1
                    ;;
                pcie)
                    for d in ccmni0 ccmni1; do
                        ip -4 addr show "$d" 2>/dev/null | grep -q "inet " && { has_ip=1; break; }
                    done
                    ;;
            esac

            if [ "$has_ip" -eq 1 ]; then
                # 接口 IP 还在但 ping 不通 → 路由/网关可能坏了 → 重建 NAT 或补路由
                log "interface has IP but ping fails, try repair route/NAT"
                # 重刷 NAT
                /etc/init.d/fm350_web start_nat 2>/dev/null
                # 等一会再 ping
                sleep 5
                health_check && { log "repair OK"; reset_fail_count; continue; }
            fi

            # 真断网了 → 重拨
            redial

            # 结果判定
            if [ $? -ne 0 ]; then
                handle_continuous_fail
                [ $? -eq 2 ] && { log "exit main"; break; }
                # 退避: 10s, 20s, 30s, ... 最长 120s
                local fc=$(cat "$LOCK_FAIL_FILE" 2>/dev/null || echo "1")
                local backoff=$(( fc * 10 ))
                [ $backoff -gt 120 ] && backoff=120
                log "backoff ${backoff}s before next retry"
                sleep "$backoff"
            else
                reset_fail_count
                log "重拨成功, 进入健康循环"
            fi
        fi
    done
}

# 命令行接口
case "${1:-}" in
    dial)    log "manual dial"; main ;;
    stop)    log "manual stop"; save_s "stopped"; kill $$ 2>/dev/null ;;
    redial)  redial ;;
    mode)    detect_mode ;;
    state)   get_s ;;
    status)  cat <<EOF
mode:   $(detect_mode)
state:  $(get_s)
fail:   $(cat "$LOCK_FAIL_FILE" 2>/dev/null || echo "0")
EOF
    *)       main ;;
esac
