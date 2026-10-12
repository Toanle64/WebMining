#!/data/data/com.termux/files/usr/bin/bash
clear
echo -e "\e[1;36m=== VERUS MINER - ONE CLICK ===\e[0m"
echo "Đang chuẩn bị..."

pkg install -y libjansson wget > /dev/null 2>&1
mkdir -p $HOME/vr && cd $HOME/vr
[ ! -f ccminer ] && wget -q https://raw.githubusercontent.com/Darktron/pre-compiled/generic/ccminer -O ccminer && chmod +x ccminer

echo
read -p "1. Địa chỉ ví (R...): " WALLET
read -p "2. Tên máy [phone1]: " WORKER
WORKER=${WORKER:-phone1}
read -p "3. Số thread [6]: " THREADS
THREADS=${THREADS:-6}

echo
echo "Chọn pool:"
echo "  1 = LuckPool Asia (khuyến nghị)"
echo "  2 = LuckPool NA"
echo "  3 = Vipor"
echo "  4 = Verus.farm"
read -p "Chọn (1-4) [1]: " POOL
POOL=${POOL:-1}

case $POOL in
  2) URL="stratum+tcp://na.luckpool.net:3956" ;;
  3) URL="stratum+tcp://sg.vipor.net:5040" ;;
  4) URL="stratum+tcp://verus.farm:9999" ;;
  *) URL="stratum+tcp://ap.luckpool.net:3956" ;;
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
echo -e "\e[1;32mBắt đầu đào... (Ctrl+C để dừng)\e[0m"
echo
./ccminer -c config.json
