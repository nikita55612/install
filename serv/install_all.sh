#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен быть запущен от root (sudo)"
    exit 1
fi

chmod +x install.sh
chmod +x install_proxy.sh
chmod +x install_xray.sh

./install.sh
sleep 2
./install_proxy.sh
sleep 2
./install_xray.sh

echo "Конфигурация прокси:"
cat /etc/3proxy/3proxy.cfg
echo ""
echo "Xray ссылка:"
cat /usr/local/etc/xray/link
