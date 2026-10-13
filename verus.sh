#!/data/data/com.termux/files/usr/bin/bash
# PULSE — Termux VRSC Miner (Pool / Hybrid / Solo)

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[0;90m'
N='\033[0m'; B='\033[1m'

DIR="$HOME/pulse"
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
║     ██████╗ ██╗   ██╗██╗     ███████╗    ║
║     ██╔══██╗██║   ██║██║     ██╔════╝    ║
║     ██████╔╝██║   ██║██║     ███████╗    ║
║     ██╔═══╝ ██║   ██║██║     ╚════██║    ║
║     ██║     ╚██████╔╝███████╗███████║    ║
║     ╚═╝      ╚═════╝ ╚══════╝╚══════╝    ║
║                                          ║
║        TERMUX VRSC MINER · v2            ║
╚══════════════════════════════════════════╝
EOF
  echo -e "${N}"
}

frame_top() {
  echo -e "${C}┌──────────────────────────────────────────┐${N}"
}
frame_bot() {
  echo -e "${C}└──────────────────────────────────────────┘${N}"
}
line() {
  echo -e "  ${D}────────────────────────────────────${N}"
}

ensure_miner() {
  pkg install -y libjansson wget curl >/dev/null 2>&1
  if [ ! -f "$DIR/ccminer" ]; then
    echo -e "  ${C}▸${N} Đang tải miner..."
    wget -q https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer -O "$DIR/ccminer"
    chmod +x "$DIR/ccminer"
    echo -e "  ${G}✓${N} Xong"
  fi
}

do_config() {
  banner
  echo -e "  ${W}${B}CẤU HÌNH${N}"
  line
  echo
  echo -e "  ${C}0.${N} Chế độ:"
  echo -e "     ${W}1${N}  Pool (share)     ${D}— ổn định, khuyên dùng${N}"
  echo -e "     ${W}2${N}  Hybrid Solo      ${D}— LuckPool 75% block${N}"
  echo -e "     ${W}3${N}  Solo Vipor       ${D}— chỉ khi ra full block${N}"
  echo -ne "     Chọn ${D}[1]${N}: "
  read -r MODE; MODE=${MODE:-1}

  echo
  while true; do
    echo -ne "  ${C}1.${N} Ví ${D}(R...)${N}: "
    read -r WALLET
    [[ "$WALLET" == R* && ${#WALLET} -gt 20 ]] && break
    echo -e "     ${R}✗ Sai định dạng R-address${N}"
  done

  echo -ne "  ${C}2.${N} Tên máy ${D}[phone1]${N}: "
  read -r WORKER; WORKER=${WORKER:-phone1}

  CORES=$(nproc 2>/dev/null || echo 6)
  DEF=$((CORES > 2 ? CORES - 1 : CORES))
  echo -ne "  ${C}3.${N} Thread ${D}[${DEF}/${CORES}]${N}: "
  read -r THREADS; THREADS=${THREADS:-$DEF}

  PASS="x"; URL=""; PNAME=""

  case $MODE in
    2)
      echo; echo -e "  Server Hybrid: ${W}1${N} AP  ${W}2${N} NA  ${W}3${N} EU"
      echo -ne "  Chọn ${D}[1]${N}: "; read -r REG; REG=${REG:-1}
      case $REG in
        2) URL="stratum+tcp://na.luckpool.net:3956" ;;
        3) URL="stratum+tcp://eu.luckpool.net:3956" ;;
        *) URL="stratum+tcp://ap.luckpool.net:3956" ;;
      esac
      PASS="x,hybrid"; PNAME="Hybrid Solo"
      ;;
    3)
      echo; echo -e "  Solo Vipor: ${W}1${N} SG  ${W}2${N} AP  ${W}3${N} US  ${W}4${N} DE"
      echo -ne "  Chọn ${D}[1]${N}: "; read -r REG; REG=${REG:-1}
      case $REG in
        2) URL="stratum+tcp://ap.vipor.net:5045" ;;
        3) URL="stratum+tcp://us.vipor.net:5045" ;;
        4) URL="stratum+tcp://de.vipor.net:5045" ;;
        *) URL="stratum+tcp://sg.vipor.net:5045" ;;
      esac
      PNAME="Solo Vipor"
      ;;
    *)
      echo; echo -e "  Pool: ${W}1${N} LuckPool AP  ${W}2${N} LuckPool NA  ${W}3${N} Vipor  ${W}4${N} Verus.farm"
      echo -ne "  Chọn ${D}[1]${N}: "; read -r POOL; POOL=${POOL:-1}
      case $POOL in
        2) URL="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
        3) URL="stratum+tcp://sg.vipor.net:5040"; PNAME="Vipor" ;;
        4) URL="stratum+tcp://verus.farm:9999"; PNAME="Verus.farm" ;;
        *) URL="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool AP" ;;
      esac
      ;;
  esac

  cat > "$CFG" << EOL
{
  "pools": [{"url": "$URL", "timeout": 180, "disabled": 0}],
  "user": "$WALLET.$WORKER",
  "pass": "$PASS",
  "algo": "verus",
  "threads": $THREADS,
  "cpu-priority": 1
}
EOL
  cat > "$META" << EOL
WALLET=$WALLET
WORKER=$WORKER
THREADS=$THREADS
PNAME=$PNAME
URL=$URL
EOL

  echo
  echo -e "  ${G}✓ Đã lưu cấu hình${N}"
  echo -e "    Mode : ${W}$PNAME${N}"
  echo -e "    Ví   : ${W}${WALLET:0:14}...${N}"
  echo -e "    Thread: ${W}$THREADS${N}"
  echo
  echo -ne "  Nhấn Enter để về menu..."
  read -r _
}

show_stats() {
  banner
  echo -e "  ${W}${B}THỐNG KÊ (LuckPool API)${N}"
  line
  if [ ! -f "$META" ]; then
    echo -e "  ${Y}Chưa cấu hình. Vào menu 1 trước.${N}"
    echo -ne "  Enter..."; read -r _; return
  fi
  source "$META"
  echo -e "  Ví: ${D}$WALLET${N}"
  echo
  echo -e "  ${C}▸${N} Đang lấy dữ liệu..."
  JSON=$(curl -sL --max-time 12 "https://luckpool.net/verus/miner/${WALLET}" 2>/dev/null)
  if [ -z "$JSON" ] || ! echo "$JSON" | grep -q hashrate; then
    echo -e "  ${Y}Không lấy được (pool khác LuckPool hoặc chưa đào).${N}"
    echo -e "  ${D}Hashrate live xem trong log khi đang đào (MH/s).${N}"
    echo -ne "  Enter..."; read -r _; return
  fi

  if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    PY=$(command -v python3 || command -v python)
    echo "$JSON" | $PY -c "
import sys, json
try:
  d=json.load(sys.stdin)
  print('  ┌────────────────────────────────────┐')
  print('  │  Hashrate    :', d.get('hashrateString','?'))
  print('  │  Balance     :', d.get('balance',0), 'VRSC')
  print('  │  Immature    :', d.get('immature',0), 'VRSC')
  print('  │  Đã trả      :', d.get('paid',0), 'VRSC')
  print('  │  Shares      :', d.get('shares','?'))
  print('  │  Efficiency  :', str(d.get('efficiency','?'))+'%')
  print('  │  Luck        :', d.get('estimatedLuck','?'))
  print('  └────────────────────────────────────┘')
except Exception as e:
  print('  Lỗi parse:', e)
"
  else
    echo -e "  ${D}$JSON${N}" | head -c 500
    echo
  fi
  echo
  echo -e "  ${D}API: luckpool.net/verus/miner/...${N}"
  echo -ne "  Enter về menu..."
  read -r _
}

start_mine() {
  banner
  if [ ! -f "$CFG" ]; then
    echo -e "  ${Y}Chưa có config — chuyển sang cấu hình.${N}"
    sleep 1
    do_config
  fi
  [ -f "$META" ] && source "$META"
  ensure_miner

  frame_top
  echo -e "${C}│${N} ${W}${B}PULSE LOG${N}  ${D}Ctrl+C = dừng & về menu${N}"
  echo -e "${C}│${N} Mode: ${W}${PNAME:-?}${N}  Thread: ${W}${THREADS:-?}${N}"
  echo -e "${C}│${N} ${D}Dòng xanh = hashrate / accepted share${N}"
  frame_bot
  echo
  echo -e "  ${C}▸ Khởi động ccminer...${N}"
  echo -e "  ${D}────────────────────────────────────────${N}"
  cd "$DIR" || exit 1
  ./ccminer -c config.json 2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -qiE 'H/s|MH/s|accepted|yes!'; then
      echo -e "  ${G}│${N} $line"
    elif echo "$line" | grep -qiE 'error|reject|fail'; then
      echo -e "  ${R}│${N} $line"
    else
      echo -e "  ${D}│${N} $line"
    fi
  done
  echo
  echo -e "  ${Y}Miner đã dừng.${N}"
  echo -ne "  Enter về menu..."
  read -r _
}

main_menu() {
  while true; do
    banner
    ensure_miner 2>/dev/null
    if [ -f "$META" ]; then
      source "$META"
      echo -e "  ${D}Config: ${PNAME:-?} · ${WALLET:0:10}... · t=${THREADS}${N}"
      line
    fi
    echo
    echo -e "  ${W}${B}MENU${N}"
    echo -e "     ${C}1${N}  Cấu hình (pool / hybrid / solo)"
    echo -e "     ${C}2${N}  Bắt đầu đào"
    echo -e "     ${C}3${N}  Xem hashrate & số dư (LuckPool)"
    echo -e "     ${C}4${N}  Thoát"
    echo
    echo -ne "  Chọn ${D}[2]${N}: "
    read -r CH; CH=${CH:-2}
    case $CH in
      1) do_config ;;
      2) start_mine ;;
      3) show_stats ;;
      4) echo -e "  ${G}Bye.${N}"; exit 0 ;;
      *) ;;
    esac
  done
}

main_menu
