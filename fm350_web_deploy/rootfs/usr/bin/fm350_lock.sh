#!/bin/sh
# FM350 锁网 + 锁频 + 锁频段 工具脚本
# ========================================
# AT 命令速查 (FM350):
#   AT+COPS=0                 自动选网
#   AT+COPS=1,2,"46000"       锁网 (mode=1 手动, format=2 数字)
#   AT%LOCK?                  查询当前锁频锁网状态
#   AT%LOCK=0                 全解锁 (自由选网选频)
#   AT%LOCK=1,<band>,<freq>   锁频段+锁频点
#   AT%CBAND?                 查询频段配置
#   AT%CBAND=1,77             锁 n77 频段 (FM350: n1/n3/n5/n7/n8/n28/n41/n77/n78/n79)
#   AT%CBAND=1,41,78          锁 n41+n78 (多频段逗号分隔)
#   AT%CBAND=0                清除频段锁定 (恢复自由选频)
#   AT%FREQLOCK=1,24900       锁指定频点
#   AT%FREQLOCK=0             解锁频点

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/at_helper.sh"

# FM350 频段编号表 (MTK), 用于 UI 展示
# NR: n1=1, n3=3, n5=5, n7=7, n8=8, n28=28, n41=41, n77=77, n78=78, n79=79
# LTE: B1=1, B3=3, B5=5, B7=7, B8=8, B20=20, B28=28, B38=38, B40=40, B41=41

# ---- 查询 ----
lock_status() {
    local cops=$(at_cmd "AT+COPS?" 3000 | at_clean)
    local lock=$(at_cmd "AT%LOCK?" 3000 | at_clean)
    local cband=$(at_cmd "AT%CBAND?" 3000 | at_clean)
    local freqlock=$(at_cmd "AT%FREQLOCK?" 3000 | at_clean)
    local hcsq=$(at_cmd "AT%HCSQ?" 3000 | at_clean)
    local op=$(at_get_operator)
    local csq=$(at_get_csq)

    cat <<JSON
{"cops":"$(echo "$cops" | json_escape)","lock":"$(echo "$lock" | json_escape)","cband":"$(echo "$cband" | json_escape)","freqlock":"$(echo "$freqlock" | json_escape)","hcsq":"$(echo "$hcsq" | json_escape)","operator":"$op","csq":"$csq"}
JSON
}

# ---- 自动选网 (清除所有锁) ----
lock_auto() {
    echo "=== 解锁所有 ==="
    at_cmd "AT+COPS=0" 3000 | at_clean
    at_cmd "AT%LOCK=0" 3000 | at_clean
    at_cmd "AT%CBAND=0" 3000 | at_clean
    at_cmd "AT%FREQLOCK=0" 3000 | at_clean
    echo ""
    echo "OK: 已恢复自动选网选频"
    lock_status
}

# ---- 锁网 (按 MCC/MNC) ----
lock_net() {
    local mccmnc="$1"       # 46000 / 46001 / 46003 / 46007 / 46008 ...
    [ -z "$mccmnc" ] && {
        echo "FAIL: need MCCMNC (e.g. 46000=移动, 46001=联通, 46003=电信, 46008=广电)"
        return 1
    }

    echo "=== 锁网到 PLMN $mccmnc ==="
    # AT+COPS=1,2,<MCCMNC>  (1=手动, 2=数字格式)
    at_cmd "AT+COPS=1,2,\"$mccmnc\"" 8000 | at_clean
    sleep 2
    lock_status
}

# ---- 锁频段 ----
lock_band() {
    # band 是 FM350 频段编号, 逗号分隔多频段
    # 常用: n78=78 (5G 主力), n41=41, n28=28, n77=77
    # LTE: B3=3, B41=41, B38=38 等
    local band="$1"
    [ -z "$band" ] && { echo "FAIL: need band e.g. 78 (n78) or 41,78 (n41+n78)"; return 1; }

    echo "=== 锁频段 $band ==="
    at_cmd "AT%CBAND=1,$band" 5000 | at_clean
    sleep 2
    lock_status
}

# ---- 锁频点 ----
lock_freq() {
    # freq 是 ARFCN / SSB 频点号
    # FR1 (Sub-6): n78 常用 632688-672624, n41 常用 499200+, n28 常用 145408-158944
    local freq="$1"
    [ -z "$freq" ] && { echo "FAIL: need freq ARFCN, e.g. 632688"; return 1; }

    echo "=== 锁频点 $freq ==="
    at_cmd "AT%FREQLOCK=1,$freq" 5000 | at_clean
    sleep 2
    lock_status
}

# ---- 一键锁网锁频 (组合) ----
lock_full() {
    # USAGE: lock_full <mccmnc> <band> [freq]
    local mccmnc="$1" band="$2" freq="${3:-}"
    [ -z "$mccmnc" ] || [ -z "$band" ] && {
        echo "FAIL: need mccmnc & band"
        return 1
    }

    echo "=== 组合锁网锁频 ==="
    echo "1) 锁网 PLMN $mccmnc"
    at_cmd "AT+COPS=1,2,\"$mccmnc\"" 8000 | at_clean
    sleep 1

    echo "2) 锁频段 $band"
    at_cmd "AT%CBAND=1,$band" 5000 | at_clean
    sleep 1

    if [ -n "$freq" ]; then
        echo "3) 锁频点 $freq"
        at_cmd "AT%FREQLOCK=1,$freq" 5000 | at_clean
    fi

    sleep 2
    echo "=== 当前状态 ==="
    lock_status
}

# ---- 列可用运营商 ----
lock_plmns() {
    echo "=== 扫描可用 PLMN (可能需要 10-30 秒) ==="
    at_cmd "AT+COPS=?" 30000 | at_clean
}

# ---- 列频段表 ----
lock_band_table() {
    cat <<TBL
FM350 常用频段编号:
  5G NR: n1=1, n3=3, n5=5, n7=7, n8=8, n28=28, n41=41, n77=77, n78=78, n79=79
  LTE:   B1=1, B3=3, B5=5, B7=7, B8=8, B20=20, B28=28, B38=38, B40=40, B41=41
  移动主力: n41(41) + n78(78)
  联通主力: n78(78) + n41(41)
  电信主力: n78(78) + n28(28)
  n7/n8: 欧洲/东南亚常见, n7=7(2.5G-2.6G), n8=8(900MHz)
TBL
}

case "${1:-status}" in
    status|show)  lock_status ;;
    auto|unlock|free) lock_auto ;;
    net|plmn)     lock_net "$2" ;;
    band)         lock_band "$2" ;;
    freq|arfcn)   lock_freq "$2" ;;
    full|all)     lock_full "$2" "$3" "$4" ;;
    scan|plmns)   lock_plmns ;;
    help|table)   lock_band_table ;;
    *)
        echo "usage: $0 status | auto | net <MCCMNC> | band <ID> | freq <ARFCN> | full <MCCMNC> <band> [freq] | scan | help"
        echo "example: $0 net 46001       # 锁联通"
        echo "         $0 band 78         # 锁 n78"
        echo "         $0 full 46001 78 632688  # 全锁"
        exit 1 ;;
esac
