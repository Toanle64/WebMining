#!/data/data/com.termux/files/usr/bin/bash
# Verus Termux Miner - One Click (UI optimized)

# Colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
B='\033[1;34m'
M='\033[0;35m'
W='\033[1;37m'
D='\033[0;90m'
N='\033[0m'
BOLD='\033[1m'

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
║         TERMUX MINER · ONE CLICK         ║
╚══════════════════════════════════════════╝
BANNER
echo -e "${N}"
echo -e "  ${D}Đào Verus Coin (VRSC) trên Android${N}"
echo -e "  ${D}────────────────────────────────────${N}"
echo

# Check arch
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

# ---- Config ----
echo -e "${W}${BOLD}  CẤU HÌNH${N}"
echo -e "  ${D}────────────────────────────────────${N}"
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
echo -ne "  ${C}3.${N} Số thread ${D}[máy có ${CORES} nhân → mặc định ${DEFAULT_T}]${N}: "
read -r THREADS
THREADS=${THREADS:-$DEFAULT_T}

echo
echo -e "  ${C}4.${N} Chọn pool:"
echo -e "     ${W}1${N}  LuckPool Asia   ${D}(khuyến nghị · min 0.0001)${N}"
echo -e "     ${W}2${N}  LuckPool NA"
echo -e "     ${W}3${N}  Vipor Singapore"
echo -e "     ${W}4${N}  Verus.farm      ${D}(phí 0.3%)${N}"
echo -ne "     Chọn ${D}[1]${N}: "
read -r POOL
POOL=${POOL:-1}

case $POOL in
  2) URL="stratum+tcp://na.luckpool.net:3956"; PNAME="LuckPool NA" ;;
  3) URL="stratum+tcp://sg.vipor.net:5040";    PNAME="Vipor SG" ;;
  4) URL="stratum+tcp://verus.farm:9999";      PNAME="Verus.farm" ;;
  *) URL="stratum+tcp://ap.luckpool.net:3956"; PNAME="LuckPool Asia" ;;
esac

cat > config.json << EOL
{
  "pools": [{"url": "$URL", "timeout": 180, "disabled": 0}],
  "user": "$WALLET.$WORKER",
  "pass": "x",
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
echo -e "    Pool   : ${W}$PNAME${N}"
echo -e "  ${D}────────────────────────────────────${N}"
echo
echo -e "  ${Y}Nhấn Ctrl+C để dừng đào${N}"
echo -e "  ${C}▸ Đang khởi động miner...${N}"
echo
sleep 1

./ccminer -c config.json
