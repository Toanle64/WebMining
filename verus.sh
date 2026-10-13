#!/data/data/com.termux/files/usr/bin/bash
# NOVA — Termux VRSC Miner (ổn định kết nối hơn)

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

ensure_deps() {
  pkg install -y libjansson wget curl >/dev/null 2>&1
  if [ ! -f "$DIR/ccminer" ]; then
    echo -e "  ${C}▸${N} Tải miner..."
    for U in \
      "https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer" \
      "https://cdn.jsdelivr.net/gh/Darktron/pre-compiled@generic/ccminer"
    do
      if wget -q --timeout=30 -O "$DIR/ccminer" "$U" 2>/dev/null; then
        chmod +x "$DIR/ccminer"
        echo -e "  ${G}✓${N} Miner OK"
        return 0
      fi
    done
    echo -e "  ${R}✗ Không tải được miner. Kiểm tra mạng.${N}"
    return 1
  fi
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
  "retry-pause": 8
}
EOL
}

do_config() {
  banner
  echo -e "  ${W}${B}CẤU HÌNH NOVA${N}"
  line
  echo
  echo -e "  ${C}0.${N} Chế độ:"
  echo -e "     ${W}1${N}  Pool (share)   ${D}— ổn định nhất${N}"
  echo -e "     ${W}2${N}  Hybrid Solo    ${D}— LuckPool 75% block${N}"
  echo -e "     ${W}3${N}  Solo Vipor     ${D}— hiếm ra block trên phone${N}"
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

  CORES=$(nproc 2>/dev/null || echo 6)
  DEF=$((CORES > 2 ? CORES - 1 : CORES))
  echo -ne "  ${C}3.${N} Thread ${D}[${DEF}/${CORES}]${N}: "
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
  "retry-pause": 8
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
    {"url": "stratum+tcp://ap.vipor.net:5045", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://sg.vipor.net:5045", "timeout": 60, "disabled": 0}
  ],
  "user": "$WALLET.$WORKER",
  "pass": "x",
  "algo": "verus",
  "threads": $THREADS,
  "cpu-priority": 1,
  "retry-pause": 8
}
EOL
      ;;
    *)
      echo; echo -e "  Pool: ${W}1${N} LuckPool AP  ${W}2${N} LuckPool NA  ${W}3${N} Vipor  ${W}4${N} Verus.farm"
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
EOL

  echo
  echo -e "  ${G}✓ Đã lưu${N}  ${W}$PNAME${N}  t=${W}$THREADS${N}"
  echo -e "  ${D}Pool dự phòng bật — giảm lỗi mất kết nối${N}"
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
  echo -e "  Ví: ${D}${WALLET:0:16}...${N}"
  echo -e "  ${C}▸${N} Đang tải..."
  JSON=$(curl -sL --max-time 15 --retry 2 "https://luckpool.net/verus/miner/${WALLET}" 2>/dev/null)
  if [ -z "$JSON" ] || ! echo "$JSON" | grep -q hashrate; then
    echo -e "  ${Y}Chưa có dữ liệu (cần đào LuckPool trước).${N}"
    echo -ne "  Enter..."; read -r _; return
  fi
  PY=$(command -v python3 || command -v python || true)
  if [ -n "$PY" ]; then
    echo "$JSON" | $PY -c "
import sys,json
d=json.load(sys.stdin)
print('  ┌────────────────────────────────────┐')
print('  │ Hashrate :', d.get('hashrateString','?'))
print('  │ Balance  :', d.get('balance',0), 'VRSC')
print('  │ Immature :', d.get('immature',0), 'VRSC')
print('  │ Đã trả   :', d.get('paid',0), 'VRSC')
print('  │ Shares   :', d.get('shares','?'))
print('  │ Hiệu suất:', str(d.get('efficiency','?'))+'%')
print('  └────────────────────────────────────┘')
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
  ensure_deps || { echo -ne "  Enter..."; read -r _; return; }

  if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && ! ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    echo -e "  ${Y}⚠ Mạng yếu / không ping được. Vẫn thử pool...${N}"
    sleep 1
  fi

  echo -e "${C}┌──────────────────────────────────────────┐${N}"
  echo -e "${C}│${N} ${W}${B}NOVA LOG${N}   ${D}Ctrl+C = dừng → menu${N}"
  echo -e "${C}│${N} ${PNAME:-?} · t=${THREADS:-?} · failover + auto-retry"
  echo -e "${C}│${N} ${D}Xanh = MH/s · Đỏ = lỗi kết nối${N}"
  echo -e "${C}└──────────────────────────────────────────┘${N}"
  echo
  echo -e "  ${C}▸${N} Kết nối pool..."
  echo -e "  ${D}────────────────────────────────────────${N}"

  cd "$DIR" || exit 1
  while true; do
    ./ccminer -c config.json 2>&1 | while IFS= read -r line; do
      if echo "$line" | grep -qiE 'H/s|MH/s|accepted|yes!'; then
        echo -e "  ${G}│${N} $line"
      elif echo "$line" | grep -qiE 'error|reject|fail|timed out|disconnect|connection|stratum'; then
        echo -e "  ${R}│${N} $line"
      else
        echo -e "  ${D}│${N} $line"
      fi
    done
    EXIT=${PIPESTATUS[0]}
    if [ "$EXIT" = "130" ] || [ "$EXIT" = "143" ]; then break; fi
    echo -e "  ${Y}│ Rớt kết nối (code $EXIT). Thử lại sau 10s...${N}"
    echo -e "  ${D}│ Ctrl+C để về menu${N}"
    sleep 10 || break
  done
  echo
  echo -e "  ${Y}Đã dừng.${N}"
  echo -ne "  Enter..."; read -r _
}

main_menu() {
  while true; do
    banner
    ensure_deps 2>/dev/null
    if [ -f "$META" ]; then
      source "$META"
      echo -e "  ${D}${PNAME:-?} · ${WALLET:0:10}... · t=${THREADS}${N}"
      line
    fi
    echo
    echo -e "  ${W}${B}MENU${N}"
    echo -e "     ${C}1${N}  Cấu hình"
    echo -e "     ${C}2${N}  Bắt đầu đào"
    echo -e "     ${C}3${N}  Hashrate & số dư"
    echo -e "     ${C}4${N}  Thoát"
    echo
    echo -ne "  Chọn ${D}[2]${N}: "
    read -r CH; CH=${CH:-2}
    case $CH in
      1) do_config ;;
      2) start_mine ;;
      3) show_stats ;;
      4) echo -e "  ${G}Nova bye.${N}"; exit 0 ;;
    esac
  done
}

main_menu
