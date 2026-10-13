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

scan_cores() {
  local onl conf info max=1 sys=0
  onl=$(nproc 2>/dev/null || true)
  conf=$(getconf _NPROCESSORS_CONF 2>/dev/null || true)
  info=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || true)
  if [ -d /sys/devices/system/cpu ]; then
    sys=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
  fi
  for v in "$onl" "$conf" "$info" "$sys"; do
    case "$v" in
      ''|*[!0-9]*) continue ;;
      *) [ "$v" -gt "$max" ] && max=$v ;;
    esac
  done
  case "$onl" in ''|*[!0-9]*) SCAN_ONL=$max ;; *) SCAN_ONL=$onl ;; esac
  SCAN_TOTAL=$max
  echo "$SCAN_ONL"
}

# Vùng mạng theo IP (phù hợp chọn pool hơn GPS)
# Set: GEO_CC GEO_CITY GEO_REGION_KEY(AP|NA|EU) GEO_POOL_HINT GEO_DEFAULT_NUM
detect_region() {
  GEO_CC="?"; GEO_CITY=""; GEO_REGION_KEY="AP"; GEO_POOL_HINT="LuckPool AP"; GEO_DEFAULT_NUM=1
  echo -e "  ${C}▸${N} Đang nhận vùng (IP)..."
  local j
  j=$(curl -sL --max-time 8 "https://ipapi.co/json/" 2>/dev/null) || j=""
  if [ -z "$j" ] || ! echo "$j" | grep -q country; then
    j=$(curl -sL --max-time 8 "https://ipinfo.io/json" 2>/dev/null) || j=""
  fi
  if [ -n "$j" ]; then
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
      local PY; PY=$(command -v python3 || command -v python)
      eval "$($PY -c "
import sys,json,re
raw=sys.stdin.read()
try:
 d=json.loads(raw)
except Exception:
 print('GEO_CC=\"?\";GEO_CITY=\"\"');
 sys.exit(0)
cc=(d.get('country_code') or d.get('country') or '?')
if isinstance(cc,str) and len(cc)>2: cc=cc[:2]
city=(d.get('city') or '')
print('GEO_CC=%r;GEO_CITY=%r'%(cc.upper() if isinstance(cc,str) else '?', city))
" <<< "$j" 2>/dev/null)"
    else
      GEO_CC=$(echo "$j" | grep -oE '"country_code"[[:space:]]*:[[:space:]]*"[A-Z]{2}"|"country"[[:space:]]*:[[:space:]]*"[A-Z]{2}"' | head -1 | grep -oE '[A-Z]{2}' | tail -1)
      GEO_CC=${GEO_CC:-?}
    fi
  fi

  case "$GEO_CC" in
    US|CA|MX|BR|AR|CL|CO|PE)
      GEO_REGION_KEY="NA"; GEO_POOL_HINT="LuckPool NA"; GEO_DEFAULT_NUM=2 ;;
    GB|IE|FR|DE|NL|BE|ES|IT|PL|RO|CZ|AT|CH|SE|NO|DK|FI|PT|GR|UA|RU|TR)
      GEO_REGION_KEY="EU"; GEO_POOL_HINT="LuckPool EU"; GEO_DEFAULT_NUM=3 ;;
    VN|TH|ID|MY|SG|PH|KH|LA|MM|BN|JP|KR|TW|HK|CN|IN|AU|NZ|BD|PK)
      GEO_REGION_KEY="AP"; GEO_POOL_HINT="LuckPool AP"; GEO_DEFAULT_NUM=1 ;;
    *)
      GEO_REGION_KEY="AP"; GEO_POOL_HINT="LuckPool AP (mặc định)"; GEO_DEFAULT_NUM=1 ;;
  esac

  if [ "$GEO_CC" = "?" ]; then
    echo -e "  ${Y}Không lấy được IP region → gợi ý AP${N}"
  else
    echo -e "  ${G}✓${N} Vùng: ${W}${GEO_CC}${N}${GEO_CITY:+ · $GEO_CITY} → gợi ý pool: ${W}${GEO_POOL_HINT}${N}"
  fi
}

fix_libs() {
  echo -e "  ${C}▸${N} Đồng bộ openssl + libcurl..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --reinstall openssl libcurl libjansson 2>/dev/null || pkg install -y openssl libcurl libjansson 2>/dev/null
  pkg upgrade -y openssl libcurl 2>/dev/null || true
  echo -e "  ${G}✓${N} Xong"
}

test_ccminer() {
  [ -x "$DIR/ccminer" ] || return 1
  local out; out=$("$DIR/ccminer" --help 2>&1)
  echo "$out" | grep -qi 'CANNOT LINK\|not found.*lib' && return 2
  return 0
}

compile_miner() {
  echo -e "  ${C}▸${N} Biên dịch ccminer..."
  pkg install -y libjansson build-essential clang binutils git wget >/dev/null 2>&1
  mkdir -p "$PREFIX/include/sys" 2>/dev/null
  [ -f "$PREFIX/include/linux/sysctl.h" ] && cp -n "$PREFIX/include/linux/sysctl.h" "$PREFIX/include/sys/" 2>/dev/null
  rm -rf "$DIR/src"
  git clone --depth 1 https://github.com/Darktron/ccminer.git "$DIR/src" 2>/dev/null || return 1
  cd "$DIR/src" || return 1
  chmod +x build.sh configure.sh autogen.sh 2>/dev/null
  CXX=clang++ CC=clang ./build.sh 2>&1 | tail -15
  if [ -f "$DIR/src/ccminer" ]; then
    cp "$DIR/src/ccminer" "$DIR/ccminer"; chmod +x "$DIR/ccminer"
    cd "$DIR" || true
    test_ccminer && { echo -e "  ${G}✓${N} OK"; return 0; }
  fi
  cd "$DIR" || true; return 1
}

install_miner() {
  local FORCE="${1:-0}"
  pkg install -y libjansson wget curl openssl >/dev/null 2>&1
  if [ "$FORCE" = "1" ] || [ ! -f "$DIR/ccminer" ]; then
    echo -e "  ${C}▸${N} Tải miner..."
    rm -f "$DIR/ccminer" "$DIR/ccminer.tmp"
    for U in \
      "https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer" \
      "https://cdn.jsdelivr.net/gh/Darktron/pre-compiled@generic/ccminer"
    do
      if wget -q --timeout=45 --tries=3 -O "$DIR/ccminer.tmp" "$U" 2>/dev/null && [ -s "$DIR/ccminer.tmp" ]; then
        mv "$DIR/ccminer.tmp" "$DIR/ccminer"; chmod +x "$DIR/ccminer"; break
      fi
    done
    rm -f "$DIR/ccminer.tmp"
  fi
  test_ccminer
  case $? in
    0) echo -e "  ${G}✓${N} Miner OK"; return 0 ;;
    2) fix_libs; test_ccminer && return 0; compile_miner && return 0; return 1 ;;
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

  detect_region
  echo

  ONL=$(scan_cores)
  TOTAL=${SCAN_TOTAL:-$ONL}
  if [ "$ONL" -gt 1 ] 2>/dev/null; then DEF=$((ONL - 1)); else DEF=1; fi

  echo -e "  ${C}▸${N} Core online: ${W}${ONL}${N} → thread mặc định: ${W}${DEF}${N} ${D}(max−1)${N}"
  if [ "$TOTAL" -gt "$ONL" ] 2>/dev/null; then
    echo -e "  ${D}Máy khai báo ${TOTAL} core, Termux dùng ${ONL}${N}"
  fi
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

  echo -ne "  ${C}3.${N} Thread ${D}[Enter = max−1 → ${DEF}]${N}: "
  read -r THREADS
  THREADS=${THREADS:-$DEF}

  PRIMARY=""; PNAME=""
  case $MODE in
    2)
      echo
      echo -e "  Hybrid server: ${W}1${N} AP  ${W}2${N} NA  ${W}3${N} EU"
      echo -e "  ${D}Gợi ý theo vùng ${GEO_CC}: chọn ${GEO_DEFAULT_NUM} (${GEO_POOL_HINT})${N}"
      echo -ne "  ${D}[${GEO_DEFAULT_NUM}]${N}: "
      read -r REG; REG=${REG:-$GEO_DEFAULT_NUM}
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
      echo
      # Solo Vipor: map region → default port server
      local SOLO_DEF=1
      case "$GEO_REGION_KEY" in
        NA) SOLO_DEF=3 ;;
        EU) SOLO_DEF=4 ;;
        *) SOLO_DEF=1 ;;
      esac
      echo -e "  Solo: ${W}1${N} SG  ${W}2${N} AP  ${W}3${N} US  ${W}4${N} DE"
      echo -e "  ${D}Gợi ý vùng ${GEO_CC}: chọn ${SOLO_DEF}${N}"
      echo -ne "  ${D}[${SOLO_DEF}]${N}: "
      read -r REG; REG=${REG:-$SOLO_DEF}
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
      echo
      echo -e "  Pool: ${W}1${N} LuckPool AP  ${W}2${N} LuckPool NA  ${W}3${N} Vipor SG  ${W}4${N} Verus.farm"
      # Map region: AP=1, NA=2; EU → vẫn gợi ý AP list nhưng hint EU via custom
      local PDEF=$GEO_DEFAULT_NUM
      [ "$PDEF" = "3" ] && PDEF=1   # menu pool không có EU riêng → AP + failover
      echo -e "  ${D}Gợi ý theo IP ${GEO_CC}: ${GEO_POOL_HINT} → chọn ${PDEF}${N}"
      [ "$GEO_REGION_KEY" = "EU" ] && echo -e "  ${D}(EU: Enter vẫn AP; failover có eu.luckpool.net)${N}"
      echo -ne "  ${D}[${PDEF}]${N}: "
      read -r POOL; POOL=${POOL:-$PDEF}
      case $POOL in
        2) PRIMARY="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
        3) PRIMARY="stratum+tcp://sg.vipor.net:5040"; PNAME="Vipor SG" ;;
        4) PRIMARY="stratum+tcp://verus.farm:9999"; PNAME="Verus.farm" ;;
        *) PRIMARY="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool AP" ;;
      esac
      # EU: primary eu nếu user giữ default và region EU
      if [ "$GEO_REGION_KEY" = "EU" ] && [ "$POOL" = "$PDEF" ]; then
        PRIMARY="stratum+tcp://eu.luckpool.net:3956"
        PNAME="LuckPool EU"
      fi
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
GEO_CC=$GEO_CC
EOL

  echo
  echo -e "  ${G}✓ Đã lưu${N}  ${W}$PNAME${N}  t=${W}$THREADS${N}  ${D}(${GEO_CC})${N}"
  echo -ne "  Enter..."; read -r _
}

show_stats() {
  banner
  if [ ! -f "$META" ]; then echo -e "  ${Y}Chưa cấu hình.${N}"; echo -ne "  Enter..."; read -r _; return; fi
  source "$META"
  JSON=$(curl -sL --max-time 15 --retry 2 "https://luckpool.net/verus/miner/${WALLET}" 2>/dev/null)
  if [ -z "$JSON" ] || ! echo "$JSON" | grep -q hashrate; then
    echo -e "  ${Y}Chưa có dữ liệu.${N}"; echo -ne "  Enter..."; read -r _; return
  fi
  PY=$(command -v python3 || command -v python || true)
  [ -n "$PY" ] && echo "$JSON" | $PY -c "import sys,json;d=json.load(sys.stdin);print('Hashrate',d.get('hashrateString'));print('Balance',d.get('balance'),'VRSC');print('Paid',d.get('paid'),'VRSC')"
  echo -ne "  Enter..."; read -r _
}

start_mine() {
  banner
  if [ ! -f "$CFG" ]; then echo -e "  ${Y}Chưa config.${N}"; sleep 1; do_config; fi
  [ -f "$META" ] && source "$META"
  install_miner 0 || { echo -ne "  Enter..."; read -r _; return; }
  test_ccminer; [ $? = 2 ] && { echo -e "  ${R}Lỗi lib — menu 4${N}"; echo -ne "  Enter..."; read -r _; return; }
  echo -e "${C}┌──────────────────────────────────────────┐${N}"
  echo -e "${C}│${N} ${W}${B}NOVA LOG${N}  ${D}Ctrl+C dừng${N}"
  echo -e "${C}│${N} ${PNAME:-?} · t=${THREADS:-?} · ${GEO_CC:-?}"
  echo -e "${C}└──────────────────────────────────────────┘${N}"
  cd "$DIR" || exit 1
  FAIL=0
  while true; do
    ./ccminer -c config.json 2>&1 | while IFS= read -r line; do
      if echo "$line" | grep -qi 'CANNOT LINK'; then echo -e "  ${R}│ $line${N}"; exit 99
      elif echo "$line" | grep -qiE 'H/s|MH/s|accepted|yes!'; then echo -e "  ${G}│${N} $line"
      elif echo "$line" | grep -qiE 'error|reject|fail|timed out|disconnect'; then echo -e "  ${R}│${N} $line"
      else echo -e "  ${D}│${N} $line"; fi
    done
    EXIT=${PIPESTATUS[0]}
    [ "$EXIT" = "130" ] || [ "$EXIT" = "143" ] || [ "$EXIT" = "99" ] && break
    FAIL=$((FAIL+1)); [ "$FAIL" -ge 5 ] && break
    echo -e "  ${Y}│ Retry 5s ($FAIL/5)${N}"; sleep 5 || break
  done
  echo -ne "  Enter..."; read -r _
}

main_menu() {
  while true; do
    banner
    ONL=$(scan_cores)
    echo -e "  ${D}CPU online: ${ONL} · thread mặc định: $((ONL>1?ONL-1:1))${N}"
    [ -f "$META" ] && source "$META" && echo -e "  ${D}${PNAME:-?} · t=${THREADS} · ${GEO_CC:-}${N}"
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
