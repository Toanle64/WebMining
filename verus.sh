#!/data/data/com.termux/files/usr/bin/bash
# NOVA — Termux multi-coin miner (VRSC + XMR)

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[0;90m'
N='\033[0m'; B='\033[1m'

DIR="$HOME/nova"
CFG="$DIR/config.json"
META="$DIR/meta.env"
XMRCFG="$DIR/xmrig.json"
mkdir -p "$DIR"
cd "$DIR" || exit 1

banner() {
  clear
  echo -e "${C}"
  cat << 'EOF'
╔══════════════════════════════════════════╗
║     ███╗   ██╗ ██████╗ ██╗   ██╗ █████╗  ║
║     ████╗  ██║██╔═══██╗██║   ██║██╔══██╗ ║
║     ██╔██╗ ██║██║   ██║██║   ██║███████║ ║
║     ██║╚██╗██║██║   ██║╚██╗ ██╔╝██╔══██║ ║
║     ██║ ╚████║╚██████╔╝ ╚████╔╝ ██║  ██║ ║
║     ╚═╝  ╚═══╝ ╚═════╝   ╚═══╝  ╚═╝  ╚═╝ ║
║         MULTI-COIN · TERMUX              ║
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
  [ -d /sys/devices/system/cpu ] && sys=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
  for v in "$onl" "$conf" "$info" "$sys"; do
    case "$v" in ''|*[!0-9]*) ;; *) [ "$v" -gt "$max" ] && max=$v ;; esac
  done
  case "$onl" in ''|*[!0-9]*) SCAN_ONL=$max ;; *) SCAN_ONL=$onl ;; esac
  SCAN_TOTAL=$max
  echo "$SCAN_ONL"
}

detect_region() {
  GEO_CC="?"; GEO_CITY=""; GEO_REGION_KEY="AP"; GEO_POOL_HINT="AP"; GEO_DEFAULT_NUM=1
  echo -e "  ${C}▸${N} Đang nhận vùng (IP)..."
  local j
  j=$(curl -sL --max-time 8 "https://ipapi.co/json/" 2>/dev/null) || j=""
  [ -z "$j" ] && j=$(curl -sL --max-time 8 "https://ipinfo.io/json" 2>/dev/null) || true
  if [ -n "$j" ]; then
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
      local PY; PY=$(command -v python3 || command -v python)
      eval "$($PY -c "
import sys,json
try:
 d=json.load(sys.stdin)
 cc=(d.get('country_code') or d.get('country') or '?')
 if isinstance(cc,str) and len(cc)>2: cc=cc[:2]
 print('GEO_CC=%r;GEO_CITY=%r'%(str(cc).upper(), d.get('city') or ''))
except Exception:
 print('GEO_CC=\"?\";GEO_CITY=\"\"')
" <<< "$j" 2>/dev/null)"
    else
      GEO_CC=$(echo "$j" | grep -oE '[A-Z]{2}' | head -1); GEO_CC=${GEO_CC:-?}
    fi
  fi
  case "$GEO_CC" in
    US|CA|MX|BR|AR) GEO_REGION_KEY="NA"; GEO_DEFAULT_NUM=2 ;;
    GB|FR|DE|NL|IT|ES|PL|RO|RU|TR) GEO_REGION_KEY="EU"; GEO_DEFAULT_NUM=3 ;;
    VN|TH|ID|MY|SG|PH|JP|KR|IN|AU) GEO_REGION_KEY="AP"; GEO_DEFAULT_NUM=1 ;;
    *) GEO_REGION_KEY="AP"; GEO_DEFAULT_NUM=1 ;;
  esac
  echo -e "  ${G}✓${N} Vùng: ${W}${GEO_CC}${N}${GEO_CITY:+ · $GEO_CITY}"
}

fix_libs() {
  echo -e "  ${C}▸${N} Đồng bộ openssl + libcurl..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --reinstall openssl libcurl libjansson 2>/dev/null || pkg install -y openssl libcurl libjansson 2>/dev/null
  echo -e "  ${G}✓${N} Xong"
}

# ─── VRSC (ccminer) ───
test_ccminer() {
  [ -x "$DIR/ccminer" ] || return 1
  local out; out=$("$DIR/ccminer" --help 2>&1)
  echo "$out" | grep -qi 'CANNOT LINK\|not found.*lib' && return 2
  return 0
}

compile_ccminer() {
  echo -e "  ${C}▸${N} Biên dịch ccminer..."
  pkg install -y libjansson build-essential clang binutils git wget >/dev/null 2>&1
  mkdir -p "$PREFIX/include/sys" 2>/dev/null
  [ -f "$PREFIX/include/linux/sysctl.h" ] && cp -n "$PREFIX/include/linux/sysctl.h" "$PREFIX/include/sys/" 2>/dev/null
  rm -rf "$DIR/src"
  git clone --depth 1 https://github.com/Darktron/ccminer.git "$DIR/src" 2>/dev/null || return 1
  cd "$DIR/src" || return 1
  chmod +x build.sh 2>/dev/null
  CXX=clang++ CC=clang ./build.sh 2>&1 | tail -12
  if [ -f "$DIR/src/ccminer" ]; then
    cp "$DIR/src/ccminer" "$DIR/ccminer"; chmod +x "$DIR/ccminer"
    cd "$DIR" || true
    test_ccminer && return 0
  fi
  cd "$DIR" || true; return 1
}

install_ccminer() {
  local FORCE="${1:-0}"
  pkg install -y libjansson wget curl openssl >/dev/null 2>&1
  if [ "$FORCE" = "1" ] || [ ! -f "$DIR/ccminer" ]; then
    echo -e "  ${C}▸${N} Tải ccminer..."
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
    0) echo -e "  ${G}✓${N} ccminer OK"; return 0 ;;
    2) fix_libs; test_ccminer && return 0; compile_ccminer && return 0; return 1 ;;
    *) [ -f "$DIR/ccminer" ] && return 0; return 1 ;;
  esac
}

# ─── XMR (xmrig) ───
install_xmrig() {
  local FORCE="${1:-0}"
  if [ "$FORCE" != "1" ] && [ -x "$DIR/xmrig" ]; then
    echo -e "  ${G}✓${N} xmrig đã có"; return 0
  fi
  echo -e "  ${C}▸${N} Cài xmrig..."
  pkg install -y wget curl git clang cmake make >/dev/null 2>&1

  # Thử package Termux
  if pkg install -y xmrig 2>/dev/null && command -v xmrig >/dev/null 2>&1; then
    XMRBIN=$(command -v xmrig)
    cp "$XMRBIN" "$DIR/xmrig" 2>/dev/null || ln -sf "$XMRBIN" "$DIR/xmrig"
    chmod +x "$DIR/xmrig" 2>/dev/null
    echo -e "  ${G}✓${N} xmrig từ pkg"
    return 0
  fi

  # Biên dịch từ source (không hwloc — ổn RandomX)
  echo -e "  ${C}▸${N} Biên dịch xmrig (~5–20 phút)..."
  rm -rf "$DIR/xmrig-src"
  if ! git clone --depth 1 https://github.com/xmrig/xmrig.git "$DIR/xmrig-src" 2>/dev/null; then
    echo -e "  ${R}✗ Clone xmrig thất bại${N}"; return 1
  fi
  mkdir -p "$DIR/xmrig-src/build"
  cd "$DIR/xmrig-src/build" || return 1
  cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF 2>&1 | tail -5
  make -j"$(nproc 2>/dev/null || echo 2)" 2>&1 | tail -10
  if [ -f "$DIR/xmrig-src/build/xmrig" ]; then
    cp "$DIR/xmrig-src/build/xmrig" "$DIR/xmrig"
    chmod +x "$DIR/xmrig"
    cd "$DIR" || true
    echo -e "  ${G}✓${N} xmrig biên dịch OK"
    return 0
  fi
  cd "$DIR" || true
  echo -e "  ${R}✗ Biên dịch xmrig thất bại${N}"
  return 1
}

write_xmr_config() {
  local WALLET="$1" WORKER="$2" THREADS="$3" URL="$4"
  cat > "$XMRCFG" << EOL
{
  "autosave": false,
  "cpu": {
    "enabled": true,
    "huge-pages": false,
    "hw-aes": null,
    "priority": 1,
    "max-threads-hint": 100,
    "asm": true,
    "argon2-impl": null,
    "cn/0": false,
    "cn-lite/0": false
  },
  "donate-level": 1,
  "donate-over-proxy": 0,
  "pools": [
    {
      "algo": "rx/0",
      "url": "$URL",
      "user": "$WALLET",
      "pass": "$WORKER",
      "keepalive": true,
      "tls": false
    }
  ],
  "print-time": 60,
  "retries": 5,
  "retry-pause": 5
}
EOL
  # Giới hạn thread nếu xmrig hỗ trợ qua env — config max-threads-hint đã có
  # Thread cứng: tạo file override đơn giản bằng CLI khi chạy
  echo "$THREADS" > "$DIR/xmr_threads"
}

do_config() {
  banner
  echo -e "  ${W}${B}CẤU HÌNH NOVA${N}"
  line
  detect_region
  echo

  ONL=$(scan_cores)
  if [ "$ONL" -gt 1 ] 2>/dev/null; then DEF=$((ONL - 1)); else DEF=1; fi
  echo -e "  ${C}▸${N} Core online: ${W}${ONL}${N} → thread mặc định: ${W}${DEF}${N}"
  echo

  echo -e "  ${C}COIN${N}"
  echo -e "     ${W}1${N}  Verus (VRSC)     ${D}— VerusHash · phone ổn${N}"
  echo -e "     ${W}2${N}  Monero (XMR)     ${D}— RandomX · nóng hơn, lời rất thấp trên phone${N}"
  echo -ne "     Chọn ${D}[1]${N}: "
  read -r COIN; COIN=${COIN:-1}

  case $COIN in
    2) config_xmr "$ONL" "$DEF" ;;
    *) config_vrsc "$ONL" "$DEF" ;;
  esac
}

config_vrsc() {
  local ONL="$1" DEF="$2"
  echo
  echo -e "  ${C}0.${N} Chế độ: ${W}1${N} Pool  ${W}2${N} Hybrid  ${W}3${N} Solo"
  echo -ne "     Chọn ${D}[1]${N}: "
  read -r MODE; MODE=${MODE:-1}

  while true; do
    echo -ne "  ${C}1.${N} Ví VRSC ${D}(R...)${N}: "
    read -r WALLET
    [[ "$WALLET" == R* && ${#WALLET} -gt 20 ]] && break
    echo -e "     ${R}✗ Cần địa chỉ bắt đầu bằng R${N}"
  done

  echo -ne "  ${C}2.${N} Tên máy ${D}[phone1]${N}: "
  read -r WORKER; WORKER=${WORKER:-phone1}
  echo -ne "  ${C}3.${N} Thread ${D}[Enter = max−1 → ${DEF}]${N}: "
  read -r THREADS; THREADS=${THREADS:-$DEF}

  PRIMARY=""; PNAME=""
  case $MODE in
    2)
      echo -e "  Hybrid: ${W}1${N} AP  ${W}2${N} NA  ${W}3${N} EU  ${D}[${GEO_DEFAULT_NUM}]${N}"
      echo -ne "  "; read -r REG; REG=${REG:-$GEO_DEFAULT_NUM}
      case $REG in
        2) PRIMARY="stratum+tcp://na.luckpool.net:3956" ;;
        3) PRIMARY="stratum+tcp://eu.luckpool.net:3956" ;;
        *) PRIMARY="stratum+tcp://ap.luckpool.net:3956" ;;
      esac
      PNAME="VRSC Hybrid"
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
      echo -e "  Solo Vipor: ${W}1${N} SG  ${W}2${N} AP  ${W}3${N} US  ${W}4${N} DE"
      echo -ne "  ${D}[1]${N}: "; read -r REG; REG=${REG:-1}
      case $REG in
        2) PRIMARY="stratum+tcp://ap.vipor.net:5045" ;;
        3) PRIMARY="stratum+tcp://us.vipor.net:5045" ;;
        4) PRIMARY="stratum+tcp://de.vipor.net:5045" ;;
        *) PRIMARY="stratum+tcp://sg.vipor.net:5045" ;;
      esac
      PNAME="VRSC Solo"
      cat > "$CFG" << EOL
{
  "pools": [{"url": "$PRIMARY", "timeout": 60, "disabled": 0}],
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
      local PDEF=$GEO_DEFAULT_NUM; [ "$PDEF" = "3" ] && PDEF=1
      echo -e "  Pool: ${W}1${N} LuckPool AP  ${W}2${N} NA  ${W}3${N} Vipor  ${W}4${N} Verus.farm"
      echo -e "  ${D}Gợi ý: ${PDEF}${N}"
      echo -ne "  ${D}[${PDEF}]${N}: "; read -r POOL; POOL=${POOL:-$PDEF}
      case $POOL in
        2) PRIMARY="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
        3) PRIMARY="stratum+tcp://sg.vipor.net:5040"; PNAME="Vipor SG" ;;
        4) PRIMARY="stratum+tcp://verus.farm:9999"; PNAME="Verus.farm" ;;
        *) PRIMARY="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool AP" ;;
      esac
      if [ "$GEO_REGION_KEY" = "EU" ] && [ "$POOL" = "$PDEF" ]; then
        PRIMARY="stratum+tcp://eu.luckpool.net:3956"; PNAME="LuckPool EU"
      fi
      cat > "$CFG" << EOL
{
  "pools": [
    {"url": "$PRIMARY", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://ap.luckpool.net:3956", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://na.luckpool.net:3956", "timeout": 60, "disabled": 0},
    {"url": "stratum+tcp://eu.luckpool.net:3956", "timeout": 60, "disabled": 0}
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
  esac

  cat > "$META" << EOL
COIN=VRSC
WALLET=$WALLET
WORKER=$WORKER
THREADS=$THREADS
PNAME=$PNAME
URL=$PRIMARY
CORES=$ONL
GEO_CC=$GEO_CC
EOL
  echo -e "  ${G}✓ VRSC · $PNAME · t=$THREADS${N}"
  echo -ne "  Enter..."; read -r _
}

config_xmr() {
  local ONL="$1" DEF="$2"
  echo
  echo -e "  ${Y}⚠ XMR trên phone: hashrate thấp (vài trăm H/s), nóng máy, lời rất nhỏ.${N}"
  echo -e "  ${D}Ví Monero bắt đầu bằng 4... hoặc 8...${N}"
  echo

  while true; do
    echo -ne "  ${C}1.${N} Ví XMR: "
    read -r WALLET
    # primary 4, integrated 4, subaddress 8
    if [[ "$WALLET" == 4* || "$WALLET" == 8* ]] && [ ${#WALLET} -gt 90 ]; then break; fi
    echo -e "     ${R}✗ Địa chỉ XMR không hợp lệ${N}"
  done

  echo -ne "  ${C}2.${N} Worker ${D}[phone1]${N}: "
  read -r WORKER; WORKER=${WORKER:-phone1}
  echo -ne "  ${C}3.${N} Thread ${D}[Enter = max−1 → ${DEF}]${N}: "
  read -r THREADS; THREADS=${THREADS:-$DEF}

  echo
  echo -e "  Pool XMR:"
  echo -e "     ${W}1${N}  SupportXMR   ${D}pool.supportxmr.com:3333${N}"
  echo -e "     ${W}2${N}  Nanopool     ${D}xmr-asia1.nanopool.org:14444${N}"
  echo -e "     ${W}3${N}  MoneroOcean  ${D}gulf.moneroocean.stream:10128 (auto coin)${N}"
  local XDEF=1
  [ "$GEO_REGION_KEY" = "NA" ] && XDEF=1
  [ "$GEO_REGION_KEY" = "EU" ] && XDEF=1
  echo -ne "     Chọn ${D}[${XDEF}]${N}: "
  read -r XP; XP=${XP:-$XDEF}

  case $XP in
    2)
      if [ "$GEO_REGION_KEY" = "NA" ]; then
        PRIMARY="xmr-us-east1.nanopool.org:14444"
      elif [ "$GEO_REGION_KEY" = "EU" ]; then
        PRIMARY="xmr-eu1.nanopool.org:14444"
      else
        PRIMARY="xmr-asia1.nanopool.org:14444"
      fi
      PNAME="Nanopool XMR"
      ;;
    3)
      PRIMARY="gulf.moneroocean.stream:10128"
      PNAME="MoneroOcean"
      ;;
    *)
      PRIMARY="pool.supportxmr.com:3333"
      PNAME="SupportXMR"
      ;;
  esac

  write_xmr_config "$WALLET" "$WORKER" "$THREADS" "$PRIMARY"

  cat > "$META" << EOL
COIN=XMR
WALLET=$WALLET
WORKER=$WORKER
THREADS=$THREADS
PNAME=$PNAME
URL=$PRIMARY
CORES=$ONL
GEO_CC=$GEO_CC
EOL
  echo -e "  ${G}✓ XMR · $PNAME · t=$THREADS${N}"
  echo -ne "  Enter..."; read -r _
}

show_stats() {
  banner
  if [ ! -f "$META" ]; then echo -e "  ${Y}Chưa cấu hình.${N}"; echo -ne "  Enter..."; read -r _; return; fi
  source "$META"
  echo -e "  Coin: ${W}${COIN:-?}${N}  Pool: ${PNAME:-?}"
  if [ "${COIN:-VRSC}" = "VRSC" ]; then
    JSON=$(curl -sL --max-time 12 "https://luckpool.net/verus/miner/${WALLET}" 2>/dev/null)
    if [ -n "$JSON" ] && echo "$JSON" | grep -q hashrate; then
      PY=$(command -v python3 || command -v python || true)
      [ -n "$PY" ] && echo "$JSON" | $PY -c "import sys,json;d=json.load(sys.stdin);print('Hashrate',d.get('hashrateString'));print('Balance',d.get('balance'),'VRSC');print('Paid',d.get('paid'),'VRSC')"
    else
      echo -e "  ${Y}Chưa có dữ liệu LuckPool.${N}"
    fi
  else
    echo -e "  ${D}Xem pool web:${N}"
    echo -e "  SupportXMR: https://supportxmr.com/#/dashboard"
    echo -e "  Nanopool:   https://xmr.nanopool.org/account/${WALLET}"
    echo -e "  MoneroOcean: https://moneroocean.stream/"
  fi
  echo -ne "  Enter..."; read -r _
}

start_mine() {
  banner
  if [ ! -f "$META" ]; then echo -e "  ${Y}Chưa config.${N}"; sleep 1; do_config; fi
  source "$META"

  if [ "${COIN:-VRSC}" = "XMR" ]; then
    install_xmrig 0 || { echo -ne "  Enter..."; read -r _; return; }
    [ ! -f "$XMRCFG" ] && { echo -e "  ${Y}Thiếu config XMR.${N}"; echo -ne "  Enter..."; read -r _; return; }
    local T=${THREADS:-2}
    echo -e "${C}┌──────────────────────────────────────────┐${N}"
    echo -e "${C}│${N} ${W}${B}NOVA XMR${N}  ${D}Ctrl+C dừng${N}"
    echo -e "${C}│${N} ${PNAME} · t=${T}"
    echo -e "${C}└──────────────────────────────────────────┘${N}"
    cd "$DIR" || exit 1
    FAIL=0
    while true; do
      ./xmrig -c xmrig.json -t "$T" 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -qiE 'accepted|speed|H/s'; then echo -e "  ${G}│${N} $line"
        elif echo "$line" | grep -qiE 'error|reject|fail|disconnect'; then echo -e "  ${R}│${N} $line"
        else echo -e "  ${D}│${N} $line"; fi
      done
      EXIT=${PIPESTATUS[0]}
      [ "$EXIT" = "130" ] || [ "$EXIT" = "143" ] && break
      FAIL=$((FAIL+1)); [ "$FAIL" -ge 5 ] && break
      echo -e "  ${Y}│ Retry 5s ($FAIL/5)${N}"; sleep 5 || break
    done
  else
    install_ccminer 0 || { echo -ne "  Enter..."; read -r _; return; }
    test_ccminer; [ $? = 2 ] && { echo -e "  ${R}Lỗi lib — menu 4${N}"; echo -ne "  Enter..."; read -r _; return; }
    echo -e "${C}┌──────────────────────────────────────────┐${N}"
    echo -e "${C}│${N} ${W}${B}NOVA VRSC${N}  ${D}Ctrl+C dừng${N}"
    echo -e "${C}│${N} ${PNAME:-?} · t=${THREADS:-?}"
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
  fi
  echo -ne "  Enter..."; read -r _
}

main_menu() {
  while true; do
    banner
    ONL=$(scan_cores)
    echo -e "  ${D}CPU online: ${ONL} · thread mặc định: $((ONL>1?ONL-1:1))${N}"
    if [ -f "$META" ]; then
      source "$META"
      echo -e "  ${D}${COIN:-VRSC} · ${PNAME:-?} · t=${THREADS}${N}"
    fi
    line
    echo
    echo -e "  ${W}${B}MENU${N}"
    echo -e "     ${C}1${N}  Cấu hình (chọn coin)"
    echo -e "     ${C}2${N}  Bắt đầu đào"
    echo -e "     ${C}3${N}  Thống kê / link pool"
    echo -e "     ${C}4${N}  Sửa lib + cập nhật miner"
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
        if [ -f "$META" ]; then source "$META"; fi
        if [ "${COIN:-VRSC}" = "XMR" ]; then install_xmrig 1; else install_ccminer 1; fi
        echo -ne "  Enter..."; read -r _
        ;;
      5) exit 0 ;;
    esac
  done
}

main_menu
