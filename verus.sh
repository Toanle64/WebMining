#!/data/data/com.termux/files/usr/bin/bash
# Verus Termux Miner - One Click (Pool / Hybrid / Solo)

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; W='\033[1;37m'; D='\033[0;90m'
N='\033[0m'; BOLD='\033[1m'

clear
echo -e "${C}"
cat << 'BANNER'
╔══════════════════════════════════════════╗
║                                          ║
║     ██╗   ██╗███████╗██████╗ ██╗   ██╗   ║
║     ██║   ██║██╔════╝██╔══██╗██║   ██║   ║
║     ██║   ██║█████╗  ██████╔╝██║   ██║   ║
║     ╚██╗ ██╔╝██╔══╝  ██╔══██╗██║   ██║   ║
║      ╚████╔╝ ███████╗██║  ██║╚██████╔╝   ║
║       ╚═══╝  ╚══════╝╚═╝  ╚═╝ ╚═════╝    ║
║                                          ║
║     TERMUX · POOL / HYBRID / SOLO        ║
╚══════════════════════════════════════════╝
BANNER
echo -e "${N}"
echo -e "  ${D}Đào Verus Coin (VRSC) trên Android${N}"
echo -e "  ${D}────────────────────────────────────${N}"
echo

ARCH=$(uname -m 2>/dev/null || echo unknown)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
  echo -e "  ${Y}⚠  Máy không phải 64-bit (${ARCH}). Hashrate có thể thấp.${N}"
  echo
fi

echo -e "  ${C}▸${N} Đang chuẩn bị môi trường..."
pkg install -y libjansson wget >/dev/null 2>&1

mkdir -p "$HOME/vr"
cd "$HOME/vr" || exit 1

if [ ! -f ccminer ]; then
  echo -e "  ${C}▸${N} Đang tải miner (lần đầu)..."
  wget -q --show-progress https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer -O ccminer 2>/dev/null \
    || wget -q https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer -O ccminer
  chmod +x ccminer
  echo -e "  ${G}✓${N} Đã tải miner"
else
  echo -e "  ${G}✓${N} Miner đã sẵn sàng"
fi
echo

echo -e "${W}${BOLD}  CẤU HÌNH${N}"
echo -e "  ${D}────────────────────────────────────${N}"
echo

echo -e "  ${C}0.${N} Chế độ đào:"
echo -e "     ${W}1${N}  Pool (share hashrate)  ${D}— coin đều, min payout thấp${N}"
echo -e "     ${W}2${N}  Hybrid Solo (LuckPool) ${D}— tìm block: 75% thưởng${N}"
echo -e "     ${W}3${N}  Solo (Vipor)           ${D}— chỉ nhận khi tìm full block${N}"
echo -ne "     Chọn ${D}[1]${N}: "
read -r MODE
MODE=${MODE:-1}

echo
while true; do
  echo -ne "  ${C}1.${N} Địa chỉ ví ${D}(R...)${N}: "
  read -r WALLET
  if [[ "$WALLET" == R* ]] && [ ${#WALLET} -gt 20 ]; then
    break
  fi
  echo -e "     ${R}✗ Phải bắt đầu bằng R và đủ dài. Thử lại.${N}"
done

echo -ne "  ${C}2.${N} Tên máy ${D}[phone1]${N}: "
read -r WORKER
WORKER=${WORKER:-phone1}

CORES=$(nproc 2>/dev/null || echo 6)
DEFAULT_T=$((CORES > 2 ? CORES - 1 : CORES))
echo -ne "  ${C}3.${N} Số thread ${D}[máy ${CORES} nhân → mặc định ${DEFAULT_T}]${N}: "
read -r THREADS
THREADS=${THREADS:-$DEFAULT_T}

PASS="x"
PNAME=""
URL=""

case $MODE in
  2)
    echo
    echo -e "  ${C}4.${N} Server Hybrid Solo (LuckPool):"
    echo -e "     ${W}1${N}  Asia-Pacific  ${D}ap.luckpool.net${N}"
    echo -e "     ${W}2${N}  North America ${D}na.luckpool.net${N}"
    echo -e "     ${W}3${N}  Europe        ${D}eu.luckpool.net${N}"
    echo -ne "     Chọn ${D}[1]${N}: "
    read -r REG
    REG=${REG:-1}
    case $REG in
      2) URL="stratum+tcp://na.luckpool.net:3956" ;;
      3) URL="stratum+tcp://eu.luckpool.net:3956" ;;
      *) URL="stratum+tcp://ap.luckpool.net:3956" ;;
    esac
    PASS="x,hybrid"
    PNAME="LuckPool Hybrid Solo"
    echo -e "  ${Y}ℹ  Hybrid: tìm block → ~75% thưởng block; vẫn nhận share từ pool.${N}"
    ;;
  3)
    echo
    echo -e "  ${C}4.${N} Server Solo (Vipor port 5045):"
    echo -e "     ${W}1${N}  Singapore     ${D}sg.vipor.net${N}"
    echo -e "     ${W}2${N}  Asia (Korea)  ${D}ap.vipor.net${N}"
    echo -e "     ${W}3${N}  USA East      ${D}us.vipor.net${N}"
    echo -e "     ${W}4${N}  Europe        ${D}de.vipor.net${N}"
    echo -ne "     Chọn ${D}[1]${N}: "
    read -r REG
    REG=${REG:-1}
    case $REG in
      2) URL="stratum+tcp://ap.vipor.net:5045" ;;
      3) URL="stratum+tcp://us.vipor.net:5045" ;;
      4) URL="stratum+tcp://de.vipor.net:5045" ;;
      *) URL="stratum+tcp://sg.vipor.net:5045" ;;
    esac
    PASS="x"
    PNAME="Vipor Solo"
    echo -e "  ${Y}ℹ  Solo: chỉ nhận coin khi máy bạn tìm được full block (hiếm trên điện thoại).${N}"
    ;;
  *)
    echo
    echo -e "  ${C}4.${N} Chọn pool (share hashrate):"
    echo -e "     ${W}1${N}  LuckPool Asia   ${D}(min 0.0001 · khuyến nghị)${N}"
    echo -e "     ${W}2${N}  LuckPool NA"
    echo -e "     ${W}3${N}  Vipor Singapore ${D}(port 5040)${N}"
    echo -e "     ${W}4${N}  Verus.farm      ${D}(phí 0.3%)${N}"
    echo -ne "     Chọn ${D}[1]${N}: "
    read -r POOL
    POOL=${POOL:-1}
    case $POOL in
      2) URL="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
      3) URL="stratum+tcp://sg.vipor.net:5040";    PNAME="Vipor Pool" ;;
      4) URL="stratum+tcp://verus.farm:9999";      PNAME="Verus.farm" ;;
      *) URL="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool Asia" ;;
    esac
    PASS="x"
    ;;
esac

cat > config.json << EOL
{
  "pools": [{"url": "$URL", "timeout": 180, "disabled": 0}],
  "user": "$WALLET.$WORKER",
  "pass": "$PASS",
  "algo": "verus",
  "threads": $THREADS,
  "cpu-priority": 1
}
EOL

echo
echo -e "  ${D}────────────────────────────────────${N}"
echo -e "  ${G}✓ Cấu hình xong${N}"
echo -e "    Ví     : ${W}${WALLET:0:12}...${N}"
echo -e "    Worker : ${W}$WORKER${N}"
echo -e "    Thread : ${W}$THREADS${N}"
echo -e "    Mode   : ${W}$PNAME${N}"
echo -e "    URL    : ${D}$URL${N}"
echo -e "  ${D}────────────────────────────────────${N}"
echo
echo -e "  ${Y}Nhấn Ctrl+C để dừng đào${N}"
echo -e "  ${C}▸ Đang khởi động miner...${N}"
echo
sleep 1

./ccminer -c config.json
