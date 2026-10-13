#!/data/data/com.termux/files/usr/bin/bash
# NOVA — Termux VRSC Miner

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[0;90m'
N='\033[0m'; B='\033[1m'

DIR="$HOME/nova"
CFG="$DIR/config.json"
META="$DIR/meta.env"
mkdir -p "$DIR"
cd "$DIR" || exit 1

banner() {
  clear
  echo -e "${C}"
  cat << 'EOF'
╔══════════════════════════════════════════╗
║                                          ║
║     ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗  ║
║     ████╗  ██║██╔═══██╗██║   ██║██╔══██╗ ║
║     ██╔██╗ ██║██║   ██║██║   ██║███████║ ║
║     ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║ ║
║     ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║ ║
║     ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝ ║
║                                          ║
║         VRSC MINER · TERMUX              ║
╚══════════════════════════════════════════╝
EOF
  echo -e "${N}"
}

line() { echo -e "  ${D}────────────────────────────────────${N}"; }

# Quét core: online (Termux thấy) + tổng trong cpuinfo (máy có thể nhiều hơn)
scan_cores() {
  local onl conf info max=1
  onl=$(nproc 2>/dev/null || true)
  conf=$(getconf _NPROCESSORS_CONF 2>/dev/null || true)
  info=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || true)
  # online từ sysfs
  local sys=0
  if [ -d /sys/devices/system/cpu ]; then
    sys=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
  fi
  for v in "$onl" "$conf" "$info" "$sys"; do
    case "$v" in
      ''|*[!0-9]*) continue ;;
      *) [ "$v" -gt "$max" ] && max=$v ;;
    esac
  done
  # Export để do_config hiện chi tiết
  SCAN_ONL=${onl:-$max}
  SCAN_TOTAL=$max
  echo "$max"
}

fix_libs() {
  echo -e "  ${C}▸${N} Đồng bộ thư viện Termux (openssl + libcurl)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --reinstall openssl libcurl libjansson 2>/dev/null || \
    pkg install -y openssl libcurl libjansson 2>/dev/null
  pkg upgrade -y openssl libcurl 2>/dev/null || true
  echo -e "  ${G}✓${N} Đã thử sửa thư viện"
}

test_ccminer() {
  [ -x "$DIR/ccminer" ] || return 1
  local out
  out=$("$DIR/ccminer" --help 2>&1)
  if echo "$out" | grep -qi 'CANNOT LINK\|not found.*lib'; then
    return 2
  fi
  return 0
}

compile_miner() {
  echo -e "  ${C}▸${N} Biên dịch ccminer (~5–15 phút)..."
  pkg install -y libjansson build-essential clang binutils git wget >/dev/null 2>&1
  mkdir -p "$PREFIX/include/sys" 2>/dev/null
  [ -f "$PREFIX/include/linux/sysctl.h" ] && cp -n "$PREFIX/include/linux/sysctl.h" "$PREFIX/include/sys/" 2>/dev/null
  rm -rf "$DIR/src"
  git clone --depth 1 https://github.com/Darktron/ccminer.git "$DIR/src" 2>/dev/null || return 1
  cd "$DIR/src" || return 1
  chmod +x build.sh configure.sh autogen.sh 2>/dev/null
  CXX=clang++ CC=clang ./build.sh 2>&1 | tail -15
  if [ -f "$DIR/src/ccminer" ]; then
    cp "$DIR/src/ccminer" "$DIR/ccminer"
    chmod +x "$DIR/ccminer"
    cd "$DIR" || true
    test_ccminer && { echo -e "  ${G}✓${N} Biên dịch OK"; return 0; }
  fi
  cd "$DIR" || true
  echo -e "  ${R}✗ Biên dịch thất bại${N}"
  return 1
}

install_miner() {
  local FORCE="${1:-0}"
  pkg install -y libjansson wget curl openssl >/dev/null 2>&1
  if [ "$FORCE" = "1" ] || [ ! -f "$DIR/ccminer" ]; then
    echo -e "  ${C}▸${N} Tải miner prebuilt..."
    rm -f "$DIR/ccminer" "$DIR/ccminer.tmp"
    for U in \
      "https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer" \
      "https://cdn.jsdelivr.net/gh/Darktron/pre-compiled@generic/ccminer"
    do
      if wget -q --timeout=45 --tries=3 -O "$DIR/ccminer.tmp" "$U" 2>/dev/null && [ -s "$DIR/ccminer.tmp" ]; then
        mv "$DIR/ccminer.tmp" "$DIR/ccminer"
        chmod +x "$DIR/ccminer"
        break
      fi
    done
    rm -f "$DIR/ccminer.tmp"
  fi
  test_ccminer
  case $? in
    0) echo -e "  ${G}✓${N} Miner OK"; return 0 ;;
    2)
      echo -e "  ${Y}⚠ Lỗi lib. Đang sửa...${N}"
      fix_libs
      test_ccminer && return 0
      compile_miner && return 0
      return 1
      ;;
    *) [ -f "$DIR/ccminer" ] && return 0; return 1 ;;
  esac
}

write_pool_config() {
  local WALLET="$1" WORKER="$2" THREADS="$3" PASS="$4" PRIMARY="$5"
  cat > "$CFG" << EOL
{
  "pools": [
    {"url": "$PRIMARY", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://ap.luckpool.net:3956", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://na.luckpool.net:3956", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://eu.luckpool.net:3956", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://sg.vipor.net:5040", "timeout": 60, "disabled": 0}
  ],
  "user": "$WALLET.$WORKER",
  "pass": "$PASS",
  "algo": "verus",
  "threads": $THREADS,
  "cpu-priority": 1,
  "retry-pause": 5
}
EOL
}

do_config() {
  banner
  echo -e "  ${W}${B}CẤU HÌNH NOVA${N}"
  line

  CORES=$(scan_cores)
  ONL=${SCAN_ONL:-$CORES}
  TOTAL=${SCAN_TOTAL:-$CORES}
  DEF=$((ONL > 2 ? ONL - 1 : ONL))
  echo -e "  ${C}▸${N} CPU Termux thấy (online): ${W}${ONL}${N}"
  if [ "$TOTAL" -gt "$ONL" ] 2>/dev/null; then
    echo -e "  ${C}▸${N} Máy khai báo (cpuinfo/sys): ${W}${TOTAL}${N}  ${Y}← cloud phone hay cắt bớt${N}"
  fi
  echo -e "  ${D}Gợi ý thread: ${DEF} (bằng online−1). Có thể gõ ${TOTAL} hoặc 8 nếu muốn thử.${N}"
  echo -e "  ${D}Thread > online có thể không tăng hashrate (OS không giao core).${N}"
  echo

  echo -e "  ${C}0.${N} Chế độ: ${W}1${N} Pool  ${W}2${N} Hybrid  ${W}3${N} Solo"
  echo -ne "     Chọn ${D}[1]${N}: "
  read -r MODE; MODE=${MODE:-1}

  echo
  while true; do
    echo -ne "  ${C}1.${N} Ví ${D}(R...)${N}: "
    read -r WALLET
    [[ "$WALLET" == R* && ${#WALLET} -gt 20 ]] && break
    echo -e "     ${R}✗ Cần địa chỉ bắt đầu bằng R${N}"
  done

  echo -ne "  ${C}2.${N} Tên máy ${D}[phone1]${N}: "
  read -r WORKER; WORKER=${WORKER:-phone1}

  echo -ne "  ${C}3.${N} Thread ${D}[gợi ý ${DEF}, có thể gõ 8]${N}: "
  read -r THREADS; THREADS=${THREADS:-$DEF}

  PRIMARY=""; PNAME=""
  case $MODE in
    2)
      echo; echo -e "  Hybrid: ${W}1${N} AP  ${W}2${N} NA  ${W}3${N} EU"
      echo -ne "  ${D}[1]${N}: "; read -r REG; REG=${REG:-1}
      case $REG in
        2) PRIMARY="stratum+tcp://na.luckpool.net:3956" ;;
        3) PRIMARY="stratum+tcp://eu.luckpool.net:3956" ;;
        *) PRIMARY="stratum+tcp://ap.luckpool.net:3956" ;;
      esac
      PNAME="Hybrid Solo"
      cat > "$CFG" << EOL
{
  "pools": [{"url": "$PRIMARY", "timeout": 60, "disabled": 0}],
  "user": "$WALLET.$WORKER",
  "pass": "x,hybrid",
  "algo": "verus",
  "threads": $THREADS,
  "cpu-priority": 1,
  "retry-pause": 5
}
EOL
      ;;
    3)
      echo; echo -e "  Solo: ${W}1${N} SG  ${W}2${N} AP  ${W}3${N} US  ${W}4${N} DE"
      echo -ne "  ${D}[1]${N}: "; read -r REG; REG=${REG:-1}
      case $REG in
        2) PRIMARY="stratum+tcp://ap.vipor.net:5045" ;;
        3) PRIMARY="stratum+tcp://us.vipor.net:5045" ;;
        4) PRIMARY="stratum+tcp://de.vipor.net:5045" ;;
        *) PRIMARY="stratum+tcp://sg.vipor.net:5045" ;;
      esac
      PNAME="Solo Vipor"
      cat > "$CFG" << EOL
{
  "pools": [
    {"url": "$PRIMARY", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://sg.vipor.net:5045", "timeout": 60, "disabled": 0}
  ],
  "user": "$WALLET.$WORKER",
  "pass": "x",
  "algo": "verus",
  "threads": $THREADS,
  "cpu-priority": 1,
  "retry-pause": 5
}
EOL
      ;;
    *)
      echo; echo -e "  Pool: ${W}1${N} LuckPool AP  ${W}2${N} NA  ${W}3${N} Vipor  ${W}4${N} Verus.farm"
      echo -ne "  ${D}[1]${N}: "; read -r POOL; POOL=${POOL:-1}
      case $POOL in
        2) PRIMARY="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
        3) PRIMARY="stratum+tcp://sg.vipor.net:5040"; PNAME="Vipor SG" ;;
        4) PRIMARY="stratum+tcp://verus.farm:9999"; PNAME="Verus.farm" ;;
        *) PRIMARY="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool AP" ;;
      esac
      write_pool_config "$WALLET" "$WORKER" "$THREADS" "x" "$PRIMARY"
      ;;
  esac

  cat > "$META" << EOL
WALLET=$WALLET
WORKER=$WORKER
THREADS=$THREADS
PNAME=$PNAME
URL=$PRIMARY
CORES=$ONL
EOL

  echo
  echo -e "  ${G}✓ Đã lưu${N}  ${W}$PNAME${N}  t=${W}$THREADS${N}"
  echo -ne "  Enter..."; read -r _
}

show_stats() {
  banner
  echo -e "  ${W}${B}THỐNG KÊ LUCKPOOL${N}"
  line
  if [ ! -f "$META" ]; then
    echo -e "  ${Y}Chưa cấu hình.${N}"
    echo -ne "  Enter..."; read -r _; return
  fi
  source "$META"
  JSON=$(curl -sL --max-time 15 --retry 2 "https://luckpool.net/verus/miner/${WALLET}" 2>/dev/null)
  if [ -z "$JSON" ] || ! echo "$JSON" | grep -q hashrate; then
    echo -e "  ${Y}Chưa có dữ liệu.${N}"
    echo -ne "  Enter..."; read -r _; return
  fi
  PY=$(command -v python3 || command -v python || true)
  if [ -n "$PY" ]; then
    echo "$JSON" | $PY -c "
import sys,json
d=json.load(sys.stdin)
print('  Hashrate:', d.get('hashrateString','?'))
print('  Balance :', d.get('balance',0), 'VRSC')
print('  Paid    :', d.get('paid',0), 'VRSC')
"
  fi
  echo -ne "  Enter..."; read -r _
}

start_mine() {
  banner
  if [ ! -f "$CFG" ]; then
    echo -e "  ${Y}Chưa config.${N}"; sleep 1; do_config
  fi
  [ -f "$META" ] && source "$META"
  install_miner 0 || { echo -ne "  Enter..."; read -r _; return; }
  test_ccminer
  if [ $? = 2 ]; then
    echo -e "  ${R}Lỗi thư viện — menu 4 hoặc apt full-upgrade.${N}"
    echo -ne "  Enter..."; read -r _; return
  fi
  echo -e "${C}┌──────────────────────────────────────────┐${N}"
  echo -e "${C}│${N} ${W}${B}NOVA LOG${N}  ${D}Ctrl+C = dừng${N}"
  echo -e "${C}│${N} ${PNAME:-?} · t=${THREADS:-?}"
  echo -e "${C}└──────────────────────────────────────────┘${N}"
  cd "$DIR" || exit 1
  FAIL=0
  while true; do
    ./ccminer -c config.json 2>&1 | while IFS= read -r line; do
      if echo "$line" | grep -qi 'CANNOT LINK'; then
        echo -e "  ${R}│ $line${N}"
        echo -e "  ${R}Dừng. Sửa lib rồi menu 4.${N}"
        exit 99
      elif echo "$line" | grep -qiE 'H/s|MH/s|accepted|yes!'; then
        echo -e "  ${G}│${N} $line"
      elif echo "$line" | grep -qiE 'error|reject|fail|timed out|disconnect'; then
        echo -e "  ${R}│${N} $line"
      else
        echo -e "  ${D}│${N} $line"
      fi
    done
    EXIT=${PIPESTATUS[0]}
    [ "$EXIT" = "130" ] || [ "$EXIT" = "143" ] || [ "$EXIT" = "99" ] && break
    FAIL=$((FAIL+1))
    [ "$FAIL" -ge 5 ] && break
    echo -e "  ${Y}│ Thử lại 5s ($FAIL/5)${N}"
    sleep 5 || break
  done
  echo -ne "  Enter..."; read -r _
}

main_menu() {
  while true; do
    banner
    CORES=$(scan_cores)
    echo -e "  ${D}CPU online: ${SCAN_ONL:-$CORES} · tổng quét: ${SCAN_TOTAL:-$CORES}${N}"
    if [ -f "$META" ]; then
      source "$META"
      echo -e "  ${D}${PNAME:-?} · t=${THREADS}${N}"
    fi
    line
    echo
    echo -e "  ${W}${B}MENU${N}"
    echo -e "     ${C}1${N}  Cấu hình"
    echo -e "     ${C}2${N}  Bắt đầu đào"
    echo -e "     ${C}3${N}  Hashrate & số dư"
    echo -e "     ${C}4${N}  Sửa lib + miner"
    echo -e "     ${C}5${N}  Thoát"
    echo
    echo -ne "  Chọn ${D}[2]${N}: "
    read -r CH; CH=${CH:-2}
    case $CH in
      1) do_config ;;
      2) start_mine ;;
      3) show_stats ;;
      4) fix_libs; install_miner 1; echo -ne "  Enter..."; read -r _ ;;
      5) exit 0 ;;
    esac
  done
}

main_menu
