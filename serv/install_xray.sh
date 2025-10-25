#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен быть запущен от root (sudo)"
    exit 1
fi

# Установка Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

# Включение BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# Порт Xray
read -p "Введите порт Xray [443]: " xrayport
xrayport=${xrayport:-443}

if ! [[ "$xrayport" =~ ^[0-9]+$ ]] || [ "$xrayport" -lt 1024 ] || [ "$xrayport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

# Генерация UUID
uuid=$(xray uuid)

# Генерация Reality ключей

keys=$(xray x25519)
privatekey=$(echo "$keys" | awk '/PrivateKey:/ {print $2}')
publickey=$(echo "$keys" | awk '/Password:/ {print $2}')

# Генерация shortId
shortid=$(openssl rand -hex 8)

read -p "Введите домен для Reality (SNI/dest) [github.com]: " desthost
desthost=${desthost:-github.com}

name=main

# Генерация конфигурации
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $xrayport,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "email": "$name"
            "flow": "xtls-rprx-vision",
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${desthost}:443",
          "xver": 0,
          "show": false,
          "serverNames": ["${desthost}", "www.${desthost}"],
          "privateKey": "$privatekey",
          "shortIds": ["$shortid"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
    }
  ]
}
EOF

# Перезапуск Xray
systemctl restart xray

# Получение публичного IP
serverip=$(curl -s ifconfig.me)

# Генерация VLESS Reality ссылки
link="vless://$uuid@$serverip:$xrayport?security=reality&sni=github.com&fp=firefox&pbk=$publickey&sid=$shortid&spx=/&type=tcp&flow=xtls-rprx-vision&encryption=none#$name"

touch /usr/local/etc/xray/link
echo "$link" > /usr/local/etc/xray/link

# Вывод ссылки и QR-кода
echo ""
echo "Ссылка для подключения:"
echo "$link"
