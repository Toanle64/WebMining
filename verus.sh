#!/data/data/com.termux/files/usr/bin/bash
# NOVA — multi-coin Termux miner
# VRSC · XMR · MoneroOcean · ZEPH (RandomX)

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
║         MULTI-COIN · TERMUX              ║
╚══════════════════════════════════════════╝
EOF
  echo -e "${N}"
}
line() { echo -e "  ${D}────────────────────────────────────${N}"; }

# CPU + RAM
scan_hw() {
  local onl conf info max=1 sys=0
  onl=$(nproc 2>/dev/null || true)
  conf=$(getconf _NPROCESSORS_CONF 2>/dev/null || true)
  info=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || true)
  [ -d /sys/devices/system/cpu ] && sys=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
  for v in "$onl" "$conf" "$info" "$sys"; do
    case "$v" in ''|*[!0-9]*) ;; *) [ "$v" -gt "$max" ] && max=$v ;; esac
  done
  case "$onl" in ''|*[!0-9]*) HW_CORES=$max ;; *) HW_CORES=$onl ;; esac
  HW_TOTAL=$max
  # RAM MB
  local kb
  kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  HW_RAM_MB=$((kb / 1024))
  [ "$HW_RAM_MB" -lt 1 ] && HW_RAM_MB=0
  if [ "$HW_CORES" -gt 1 ] 2>/dev/null; then HW_THREADS=$((HW_CORES - 1)); else HW_THREADS=1; fi
  # Gợi ý coin: RandomX cần ~2GB+; phone yếu → VRSC
  if [ "$HW_RAM_MB" -ge 3500 ] && [ "$HW_CORES" -ge 6 ]; then
    HW_REC="XMR/MO"
    HW_REC_MSG="RAM và core khá → có thể thử MoneroOcean / XMR; VRSC vẫn ổn định hơn trên phone."
  elif [ "$HW_RAM_MB" -ge 2500 ] && [ "$HW_CORES" -ge 4 ]; then
    HW_REC="VRSC"
    HW_REC_MSG="Phone tầm trung → ưu tiên Verus (Pool). XMR chỉ thử nghiệm."
  else
    HW_REC="VRSC"
    HW_REC_MSG="RAM/core hạn chế → chỉ nên Verus Pool, thread = max−1. Tránh RandomX (nóng + chậm)."
  fi
}

detect_region() {
  GEO_CC="?"; GEO_CITY=""; GEO_REGION_KEY="AP"; GEO_DEFAULT_NUM=1
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
    fi
  fi
  case "$GEO_CC" in
    US|CA|MX|BR|AR) GEO_REGION_KEY="NA"; GEO_DEFAULT_NUM=2 ;;
    GB|FR|DE|NL|IT|ES|PL|RO|RU|TR) GEO_REGION_KEY="EU"; GEO_DEFAULT_NUM=3 ;;
    VN|TH|ID|MY|SG|PH|JP|KR|IN|AU) GEO_REGION_KEY="AP"; GEO_DEFAULT_NUM=1 ;;
    *) GEO_REGION_KEY="AP"; GEO_DEFAULT_NUM=1 ;;
  esac
  echo -e "  ${G}✓${N} Vùng: ${W}${GEO_CC:-?}${N}${GEO_CITY:+ · $GEO_CITY}"
}

fix_libs() {
  echo -e "  ${C}▸${N} Đồng bộ openssl + libcurl..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null 2>&1
  apt-get install -y --reinstall openssl libcurl libjansson 2>/dev/null || pkg install -y openssl libcurl libjansson 2>/dev/null
  echo -e "  ${G}✓${N} Xong"
}

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
  CXX=clang++ CC=clang ./build.sh 2>&1 | tail -10
  if [ -f "$DIR/src/ccminer" ]; then
    cp "$DIR/src/ccminer" "$DIR/ccminer"; chmod +x "$DIR/ccminer"
    cd "$DIR" || true; test_ccminer && return 0
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

install_xmrig() {
  local FORCE="${1:-0}"
  if [ "$FORCE" != "1" ] && [ -x "$DIR/xmrig" ]; then echo -e "  ${G}✓${N} xmrig OK"; return 0; fi
  echo -e "  ${C}▸${N} Cài xmrig..."
  pkg install -y wget curl git clang cmake make >/dev/null 2>&1
  if pkg install -y xmrig 2>/dev/null && command -v xmrig >/dev/null 2>&1; then
    cp "$(command -v xmrig)" "$DIR/xmrig" 2>/dev/null || ln -sf "$(command -v xmrig)" "$DIR/xmrig"
    chmod +x "$DIR/xmrig" 2>/dev/null
    echo -e "  ${G}✓${N} xmrig pkg"; return 0
  fi
  echo -e "  ${C}▸${N} Biên dịch xmrig (~5–20 phút)..."
  rm -rf "$DIR/xmrig-src"
  git clone --depth 1 https://github.com/xmrig/xmrig.git "$DIR/xmrig-src" 2>/dev/null || return 1
  mkdir -p "$DIR/xmrig-src/build" && cd "$DIR/xmrig-src/build" || return 1
  cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF 2>&1 | tail -4
  make -j"$(nproc 2>/dev/null || echo 2)" 2>&1 | tail -8
  if [ -f "$DIR/xmrig-src/build/xmrig" ]; then
    cp "$DIR/xmrig-src/build/xmrig" "$DIR/xmrig"; chmod +x "$DIR/xmrig"
    cd "$DIR" || true; echo -e "  ${G}✓${N} xmrig OK"; return 0
  fi
  cd "$DIR" || true; return 1
}

write_xmrig_cfg() {
  local USER="$1" PASS="$2" URL="$3" ALGO="${4:-rx/0}"
  cat > "$XMRCFG" << EOL
{
  "autosave": false,
  "cpu": { "enabled": true, "huge-pages": false, "priority": 1, "asm": true },
  "donate-level": 1,
  "pools": [{
    "algo": "$ALGO",
    "url": "$URL",
    "user": "$USER",
    "pass": "$PASS",
    "keepalive": true,
    "tls": false
  }],
  "print-time": 60,
  "retries": 5,
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
  scan_hw
  echo -e "  ${C}▸${N} CPU online: ${W}${HW_CORES}${N}  RAM: ${W}${HW_RAM_MB} MB${N}"
  echo -e "  ${C}▸${N} Thread mặc định: ${W}${HW_THREADS}${N} ${D}(max−1)${N}"
  echo -e "  ${G}★ Gợi ý: ${W}${HW_REC}${N}"
  echo -e "  ${D}${HW_REC_MSG}${N}"
  echo

  echo -e "  ${C}CHỌN COIN${N}"
  echo -e "     ${W}1${N}  Verus (VRSC)      ${D}VerusHash · khuyến nghị phone${N}"
  echo -e "     ${W}2${N}  Monero (XMR)      ${D}RandomX · nóng, lời thấp${N}"
  echo -e "     ${W}3${N}  MoneroOcean       ${D}auto RandomX coins · payout XMR${N}"
  echo -e "     ${W}4${N}  Zephyr (ZEPH)     ${D}RandomX fork · xmrig${N}"
  local CDEF=1
  [ "$HW_REC" = "XMR/MO" ] && CDEF=3
  echo -ne "     Chọn ${D}[${CDEF}]${N}: "
  read -r COIN; COIN=${COIN:-$CDEF}

  case $COIN in
    2) config_rx XMR ;;
    3) config_rx MO ;;
    4) config_rx ZEPH ;;
    *) config_vrsc ;;
  esac
}

config_vrsc() {
  echo
  echo -e "  Chế độ: ${W}1${N} Pool  ${W}2${N} Hybrid  ${W}3${N} Solo"
  echo -ne "  ${D}[1]${N}: "; read -r MODE; MODE=${MODE:-1}
  while true; do
    echo -ne "  Ví VRSC ${D}(R...)${N}: "; read -r WALLET
    [[ "$WALLET" == R* && ${#WALLET} -gt 20 ]] && break
    echo -e "  ${R}✗ Cần R...${N}"
  done
  echo -ne "  Worker ${D}[phone1]${N}: "; read -r WORKER; WORKER=${WORKER:-phone1}
  echo -ne "  Thread ${D}[Enter=${HW_THREADS}]${N}: "; read -r THREADS; THREADS=${THREADS:-$HW_THREADS}

  PRIMARY=""; PNAME=""
  case $MODE in
    2)
      echo -e "  Hybrid: 1 AP  2 NA  3 EU  [${GEO_DEFAULT_NUM}]"
      echo -ne "  "; read -r REG; REG=${REG:-$GEO_DEFAULT_NUM}
      case $REG in 2) PRIMARY="stratum+tcp://na.luckpool.net:3956" ;; 3) PRIMARY="stratum+tcp://eu.luckpool.net:3956" ;; *) PRIMARY="stratum+tcp://ap.luckpool.net:3956" ;; esac
      PNAME="VRSC Hybrid"
      cat > "$CFG" << EOL
{"pools":[{"url":"$PRIMARY","timeout":60,"disabled":0}],"user":"$WALLET.$WORKER","pass":"x,hybrid","algo":"verus","threads":$THREADS,"cpu-priority":1,"retry-pause":5}
EOL
      ;;
    3)
      echo -e "  Solo: 1 SG  2 AP  3 US  4 DE"
      echo -ne "  [1]: "; read -r REG; REG=${REG:-1}
      case $REG in 2) PRIMARY="stratum+tcp://ap.vipor.net:5045" ;; 3) PRIMARY="stratum+tcp://us.vipor.net:5045" ;; 4) PRIMARY="stratum+tcp://de.vipor.net:5045" ;; *) PRIMARY="stratum+tcp://sg.vipor.net:5045" ;; esac
      PNAME="VRSC Solo"
      cat > "$CFG" << EOL
{"pools":[{"url":"$PRIMARY","timeout":60,"disabled":0}],"user":"$WALLET.$WORKER","pass":"x","algo":"verus","threads":$THREADS,"cpu-priority":1,"retry-pause":5}
EOL
      ;;
    *)
      local PDEF=$GEO_DEFAULT_NUM; [ "$PDEF" = "3" ] && PDEF=1
      echo -e "  Pool: 1 LuckPool AP  2 NA  3 Vipor  4 Verus.farm  [${PDEF}]"
      echo -ne "  "; read -r POOL; POOL=${POOL:-$PDEF}
      case $POOL in
        2) PRIMARY="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
        3) PRIMARY="stratum+tcp://sg.vipor.net:5040"; PNAME="Vipor SG" ;;
        4) PRIMARY="stratum+tcp://verus.farm:9999"; PNAME="Verus.farm" ;;
        *) PRIMARY="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool AP" ;;
      esac
      [ "$GEO_REGION_KEY" = "EU" ] && [ "$POOL" = "$PDEF" ] && PRIMARY="stratum+tcp://eu.luckpool.net:3956" && PNAME="LuckPool EU"
      cat > "$CFG" << EOL
{"pools":[
 {"url":"$PRIMARY","timeout":60,"disabled":0},
 {"url":"stratum+tcp://ap.luckpool.net:3956","timeout":60,"disabled":0},
 {"url":"stratum+tcp://na.luckpool.net:3956","timeout":60,"disabled":0},
 {"url":"stratum+tcp://eu.luckpool.net:3956","timeout":60,"disabled":0}
],"user":"$WALLET.$WORKER","pass":"x","algo":"verus","threads":$THREADS,"cpu-priority":1,"retry-pause":5}
EOL
      ;;
  esac
  cat > "$META" << EOL
COIN=VRSC
ENGINE=ccminer
WALLET=$WALLET
WORKER=$WORKER
THREADS=$THREADS
PNAME=$PNAME
URL=$PRIMARY
CORES=$HW_CORES
RAM=$HW_RAM_MB
GEO_CC=$GEO_CC
EOL
  echo -e "  ${G}✓ VRSC · $PNAME · t=$THREADS${N}"
  echo -ne "  Enter..."; read -r _
}

# kind: XMR | MO | ZEPH
config_rx() {
  local KIND="$1"
  echo
  echo -e "  ${Y}⚠ RandomX trên phone: nóng, hashrate thấp, lời rất nhỏ.${N}"
  case $KIND in
    MO) echo -e "  ${D}MoneroOcean: auto đổi coin RandomX, trả về XMR${N}" ;;
    ZEPH) echo -e "  ${D}Zephyr: ví ZEPH (cùng format XMR-style)${N}" ;;
  esac
  echo
  while true; do
    echo -ne "  Ví (4... hoặc 8...): "; read -r WALLET
    if [[ "$WALLET" == 4* || "$WALLET" == 8* ]] && [ ${#WALLET} -gt 90 ]; then break; fi
    echo -e "  ${R}✗ Ví không hợp lệ${N}"
  done
  echo -ne "  Worker ${D}[phone1]${N}: "; read -r WORKER; WORKER=${WORKER:-phone1}
  echo -ne "  Thread ${D}[Enter=${HW_THREADS}]${N}: "; read -r THREADS; THREADS=${THREADS:-$HW_THREADS}

  local URL ALGO="rx/0" PNAME COINCODE
  case $KIND in
    MO)
      URL="gulf.moneroocean.stream:10128"
      PNAME="MoneroOcean"
      COINCODE="MO"
      ALGO=null
      ;;
    ZEPH)
      URL="zephyr.herominers.com:1123"
      PNAME="Zephyr HeroMiners"
      COINCODE="ZEPH"
      ;;
    *)
      echo -e "  Pool XMR: 1 SupportXMR  2 Nanopool Asia  3 Nanopool EU"
      echo -ne "  [1]: "; read -r XP; XP=${XP:-1}
      case $XP in
        2) URL="xmr-asia1.nanopool.org:14444"; PNAME="Nanopool Asia" ;;
        3) URL="xmr-eu1.nanopool.org:14444"; PNAME="Nanopool EU" ;;
        *) URL="pool.supportxmr.com:3333"; PNAME="SupportXMR" ;;
      esac
      COINCODE="XMR"
      ;;
  esac

  if [ "$ALGO" = "null" ]; then
    cat > "$XMRCFG" << EOL
{
  "autosave": false,
  "cpu": { "enabled": true, "huge-pages": false, "priority": 1 },
  "donate-level": 1,
  "pools": [{
    "url": "$URL",
    "user": "$WALLET",
    "pass": "$WORKER",
    "keepalive": true,
    "tls": false
  }],
  "print-time": 60,
  "retries": 5,
  "retry-pause": 5
}
EOL
  else
    write_xmrig_cfg "$WALLET" "$WORKER" "$URL" "$ALGO"
  fi

  cat > "$META" << EOL
COIN=$COINCODE
ENGINE=xmrig
WALLET=$WALLET
WORKER=$WORKER
THREADS=$THREADS
PNAME=$PNAME
URL=$URL
CORES=$HW_CORES
RAM=$HW_RAM_MB
GEO_CC=$GEO_CC
EOL
  echo -e "  ${G}✓ $COINCODE · $PNAME · t=$THREADS${N}"
  echo -ne "  Enter..."; read -r _
}

show_stats() {
  banner
  [ ! -f "$META" ] && { echo -e "  ${Y}Chưa cấu hình.${N}"; echo -ne "  Enter..."; read -r _; return; }
  source "$META"
  echo -e "  ${W}${COIN}${N} · ${PNAME} · CPU ${CORES}c · RAM ${RAM}MB"
  if [ "${ENGINE:-ccminer}" = "ccminer" ]; then
    JSON=$(curl -sL --max-time 12 "https://luckpool.net/verus/miner/${WALLET}" 2>/dev/null)
    if echo "$JSON" | grep -q hashrate; then
      PY=$(command -v python3 || command -v python || true)
      [ -n "$PY" ] && echo "$JSON" | $PY -c "import sys,json;d=json.load(sys.stdin);print('HR',d.get('hashrateString'),'| Bal',d.get('balance'),'| Paid',d.get('paid'))"
    else echo -e "  ${Y}Chưa có data LuckPool${N}"; fi
  else
    echo -e "  ${D}Dashboard pool:${N}"
    echo -e "  https://supportxmr.com/  |  https://moneroocean.stream/"
    echo -e "  https://xmr.nanopool.org/account/${WALLET}"
  fi
  echo -ne "  Enter..."; read -r _
}

start_mine() {
  banner
  [ ! -f "$META" ] && { echo -e "  ${Y}Chưa config${N}"; sleep 1; do_config; }
  source "$META"
  local T=${THREADS:-2}

  if [ "${ENGINE:-ccminer}" = "xmrig" ]; then
    install_xmrig 0 || { echo -ne "  Enter..."; read -r _; return; }
    echo -e "${C}│${N} ${W}NOVA ${COIN}${N} · ${PNAME} · t=$T  ${D}Ctrl+C dừng${N}"
    cd "$DIR" || exit 1
    FAIL=0
    while true; do
      ./xmrig -c xmrig.json -t "$T" 2>&1 | while IFS= read -r line; do
        echo "$line" | grep -qiE 'accepted|speed|H/s' && echo -e "  ${G}│${N} $line" && continue
        echo "$line" | grep -qiE 'error|reject|fail|disconnect' && echo -e "  ${R}│${N} $line" && continue
        echo -e "  ${D}│${N} $line"
      done
      EXIT=${PIPESTATUS[0]}
      [ "$EXIT" = "130" ] || [ "$EXIT" = "143" ] && break
      FAIL=$((FAIL+1)); [ "$FAIL" -ge 5 ] && break
      echo -e "  ${Y}│ Retry 5s ($FAIL/5)${N}"; sleep 5 || break
    done
  else
    install_ccminer 0 || { echo -ne "  Enter..."; read -r _; return; }
    test_ccminer; [ $? = 2 ] && { echo -e "  ${R}Lỗi lib — menu 4${N}"; echo -ne "  Enter..."; read -r _; return; }
    echo -e "${C}│${N} ${W}NOVA VRSC${N} · ${PNAME} · t=$T  ${D}Ctrl+C dừng${N}"
    cd "$DIR" || exit 1
    FAIL=0
    while true; do
      ./ccminer -c config.json 2>&1 | while IFS= read -r line; do
        echo "$line" | grep -qi 'CANNOT LINK' && echo -e "  ${R}│ $line${N}" && exit 99
        echo "$line" | grep -qiE 'H/s|MH/s|accepted|yes!' && echo -e "  ${G}│${N} $line" && continue
        echo "$line" | grep -qiE 'error|reject|fail|timed out|disconnect' && echo -e "  ${R}│${N} $line" && continue
        echo -e "  ${D}│${N} $line"
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
    scan_hw
    echo -e "  ${D}${HW_CORES} core · ${HW_RAM_MB} MB RAM · gợi ý: ${HW_REC}${N}"
    [ -f "$META" ] && source "$META" && echo -e "  ${D}${COIN:-?} · ${PNAME:-?} · t=${THREADS}${N}"
    line
    echo
    echo -e "  ${W}${B}MENU${N}"
    echo -e "     ${C}1${N}  Cấu hình (coin + pool)"
    echo -e "     ${C}2${N}  Bắt đầu đào"
    echo -e "     ${C}3${N}  Thống kê"
    echo -e "     ${C}4${N}  Sửa lib + miner"
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
        [ -f "$META" ] && source "$META"
        if [ "${ENGINE:-ccminer}" = "xmrig" ]; then install_xmrig 1; else install_ccminer 1; fi
        echo -ne "  Enter..."; read -r _
        ;;
      5) exit 0 ;;
    esac
  done
}

main_menu
