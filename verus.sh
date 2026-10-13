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

# Quét số core CPU
scan_cores() {
  local n
  n=$(nproc 2>/dev/null) || n=""
  if [ -z "$n" ] || [ "$n" -lt 1 ] 2>/dev/null; then
    n=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
  fi
  echo "$n"
}

# Sửa lệch openssl / libcurl (nguyên nhân CANNOT LINK)
fix_libs() {
  echo -e "  ${C}▸${N} Đồng bộ thư viện Termux (openssl + libcurl)..."
  # pkg upgrade có thể hỏi — dùng DEBIAN_FRONTEND
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --reinstall openssl libcurl libjansson 2>/dev/null || \
    pkg install -y openssl libcurl libjansson 2>/dev/null
  pkg upgrade -y openssl libcurl 2>/dev/null || true
  echo -e "  ${G}✓${N} Đã thử sửa thư viện"
}

# Kiểm tra binary có chạy được không
test_ccminer() {
  [ -x "$DIR/ccminer" ] || return 1
  local out
  out=$("$DIR/ccminer" --help 2>&1)
  if echo "$out" | grep -qi 'CANNOT LINK'; then
    return 2
  fi
  # exit code có thể khác 0 với --help nhưng không phải link error
  if echo "$out" | grep -qi 'CANNOT LINK\|not found.*lib'; then
    return 2
  fi
  return 0
}

# Biên dịch từ source nếu prebuilt hỏng
compile_miner() {
  echo -e "  ${C}▸${N} Biên dịch ccminer trên máy (lâu ~5–15 phút)..."
  pkg install -y libjansson build-essential clang binutils git wget >/dev/null 2>&1
  mkdir -p "$PREFIX/include/sys" 2>/dev/null
  [ -f "$PREFIX/include/linux/sysctl.h" ] && cp -n "$PREFIX/include/linux/sysctl.h" "$PREFIX/include/sys/" 2>/dev/null
  rm -rf "$DIR/src"
  if ! git clone --depth 1 https://github.com/Darktron/ccminer.git "$DIR/src" 2>/dev/null; then
    echo -e "  ${R}✗ Clone thất bại${N}"
    return 1
  fi
  cd "$DIR/src" || return 1
  chmod +x build.sh configure.sh autogen.sh 2>/dev/null
  CXX=clang++ CC=clang ./build.sh 2>&1 | tail -20
  if [ -f "$DIR/src/ccminer" ]; then
    cp "$DIR/src/ccminer" "$DIR/ccminer"
    chmod +x "$DIR/ccminer"
    cd "$DIR" || true
    if test_ccminer; then
      echo -e "  ${G}✓${N} Biên dịch thành công"
      return 0
    fi
  fi
  cd "$DIR" || true
  echo -e "  ${R}✗ Biên dịch thất bại${N}"
  return 1
}

install_miner() {
  local FORCE="${1:-0}"
  pkg install -y libjansson wget curl openssl >/dev/null 2>&1

  if [ "$FORCE" = "1" ] || [ ! -f "$DIR/ccminer" ]; then
    echo -e "  ${C}▸${N} Tải miner prebuilt (Darktron)..."
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
      echo -e "  ${Y}⚠ Lỗi thư viện (CANNOT LINK / OpenSSL). Đang sửa...${N}"
      fix_libs
      test_ccminer && { echo -e "  ${G}✓${N} Đã sửa xong"; return 0; }
      echo -e "  ${Y}Prebuilt vẫn lỗi. Biên dịch từ source...${N}"
      compile_miner && return 0
      echo -e "  ${R}✗ Không chạy được miner.${N}"
      echo -e "  ${D}Thử tay:${N}"
      echo -e "  ${W}pkg update && pkg upgrade -y${N}"
      echo -e "  ${W}pkg reinstall openssl libcurl -y${N}"
      return 1
      ;;
    *)
      if [ ! -f "$DIR/ccminer" ]; then
        echo -e "  ${R}✗ Chưa có file miner${N}"
        return 1
      fi
      echo -e "  ${G}✓${N} Miner có file (chạy thử khi đào)"
      return 0
      ;;
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
  DEF=$((CORES > 2 ? CORES - 1 : CORES))
  echo -e "  ${C}▸${N} Quét CPU: ${W}${CORES} core${N}  → gợi ý thread: ${W}${DEF}${N}"
  if [ -f /proc/cpuinfo ]; then
    MODEL=$(grep -m1 'Hardware\|model name\|Processor' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //')
    [ -n "$MODEL" ] && echo -e "  ${D}  $MODEL${N}"
  fi
  echo

  echo -e "  ${C}0.${N} Chế độ:"
  echo -e "     ${W}1${N}  Pool (share)   ${D}— ổn định nhất${N}"
  echo -e "     ${W}2${N}  Hybrid Solo    ${D}— LuckPool 75% block${N}"
  echo -e "     ${W}3${N}  Solo Vipor     ${D}— hiếm ra block${N}"
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

  echo -ne "  ${C}3.${N} Thread ${D}[máy ${CORES} core → ${DEF}]${N}: "
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
CORES=$CORES
EOL

  echo
  echo -e "  ${G}✓ Đã lưu${N}  ${W}$PNAME${N}  ${CORES} core → t=${W}$THREADS${N}"
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
  install_miner 0 || { echo -ne "  Enter..."; read -r _; return; }

  # Test trước khi loop
  test_ccminer
  TC=$?
  if [ "$TC" = "2" ]; then
    echo -e "  ${R}Miner không chạy được (lỗi thư viện OpenSSL/libcurl).${N}"
    echo -e "  ${Y}Không phải rớt mạng.${N}"
    echo
    echo -e "  Chạy trong Termux:"
    echo -e "  ${W}pkg update && pkg upgrade -y${N}"
    echo -e "  ${W}pkg reinstall openssl libcurl -y${N}"
    echo -e "  Rồi vào menu ${W}4${N} cập nhật miner / biên dịch."
    echo -ne "  Enter..."; read -r _; return
  fi

  echo -e "${C}┌──────────────────────────────────────────┐${N}"
  echo -e "${C}│${N} ${W}${B}NOVA LOG${N}   ${D}Ctrl+C = dừng → menu${N}"
  echo -e "${C}│${N} ${PNAME:-?} · ${CORES:-?}c · t=${THREADS:-?}"
  echo -e "${C}└──────────────────────────────────────────┘${N}"
  echo

  cd "$DIR" || exit 1
  FAIL=0
  while true; do
    OUT=$(mktemp)
    ./ccminer -c config.json >"$OUT" 2>&1 &
    PID=$!
    while kill -0 "$PID" 2>/dev/null; do
      if [ -s "$OUT" ]; then
        while IFS= read -r line; do
          if echo "$line" | grep -qi 'CANNOT LINK'; then
            echo -e "  ${R}│ $line${N}"
            kill "$PID" 2>/dev/null
            rm -f "$OUT"
            echo -e "  ${R}Lỗi thư viện — dừng retry. Sửa openssl/libcurl rồi menu 4.${N}"
            echo -ne "  Enter..."; read -r _; return
          elif echo "$line" | grep -qiE 'H/s|MH/s|accepted|yes!'; then
            echo -e "  ${G}│${N} $line"
          elif echo "$line" | grep -qiE 'error|reject|fail|timed out|disconnect'; then
            echo -e "  ${R}│${N} $line"
          else
            echo -e "  ${D}│${N} $line"
          fi
        done < "$OUT"
        : > "$OUT"
      fi
      sleep 0.3
    done
    wait "$PID"
    EXIT=$?
    rm -f "$OUT"
    if [ "$EXIT" = "130" ] || [ "$EXIT" = "143" ]; then break; fi
    FAIL=$((FAIL + 1))
    if [ "$FAIL" -ge 5 ]; then
      echo -e "  ${R}Thất bại $FAIL lần liên tiếp. Dừng.${N}"
      break
    fi
    echo -e "  ${Y}│ Thoát code $EXIT. Thử lại sau 5s... ($FAIL/5)${N}"
    sleep 5 || break
  done
  echo -e "  ${Y}Đã dừng.${N}"
  echo -ne "  Enter..."; read -r _
}

main_menu() {
  while true; do
    banner
    CORES=$(scan_cores)
    echo -e "  ${D}CPU: ${CORES} core${N}"
    if [ -f "$META" ]; then
      source "$META"
      echo -e "  ${D}${PNAME:-?} · ${WALLET:0:10}... · t=${THREADS}${N}"
    fi
    line
    echo
    echo -e "  ${W}${B}MENU${N}"
    echo -e "     ${C}1${N}  Cấu hình"
    echo -e "     ${C}2${N}  Bắt đầu đào"
    echo -e "     ${C}3${N}  Hashrate & số dư"
    echo -e "     ${C}4${N}  Sửa thư viện + cập nhật / biên dịch miner"
    echo -e "     ${C}5${N}  Thoát"
    echo
    echo -ne "  Chọn ${D}[2]${N}: "
    read -r CH; CH=${CH:-2}
    case $CH in
      1) do_config ;;
      2) start_mine ;;
      3) show_stats ;;
      4)
        fix_libs
        install_miner 1
        echo -ne "  Enter..."; read -r _
        ;;
      5) echo -e "  ${G}Nova bye.${N}"; exit 0 ;;
    esac
  done
}

main_menu
