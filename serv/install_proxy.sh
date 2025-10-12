#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен быть запущен от root (sudo)"
    exit 1
fi

VERSION=0.9.5

# Скачиваем и распаковываем
wget -q --show-progress --timeout=15 --tries=2 -O 3proxy.tar.gz \
  https://github.com/z3APA3A/3proxy/archive/${VERSION}.tar.gz

tar -xzf 3proxy.tar.gz
mv 3proxy-${VERSION} 3proxy
rm 3proxy.tar.gz

# Сборка
cd 3proxy
make -f Makefile.Linux
cd ..

# Установка
mkdir -p /etc/3proxy /var/log/3proxy
if [ -f 3proxy/src/3proxy ]; then
    cp 3proxy/src/3proxy /usr/local/bin/
elif [ -f 3proxy/bin/3proxy ]; then
    cp 3proxy/bin/3proxy /usr/local/bin/
else
    echo "Бинарник 3proxy не найден после сборки"
    exit 1
fi

# Удаляем исходники
rm -rf 3proxy

read -p "Введите порт для 3proxy (по умолчанию 44667): " proxyport

# Проверка ввода порта и установка значения по умолчанию
if [ -z "$proxyport" ]; then
    proxyport=44667
fi

# Проверка что порт числовой
if ! [[ "$proxyport" =~ ^[0-9]+$ ]] || [ "$proxyport" -lt 1024 ] || [ "$proxyport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

# Вычисляем порт для SOCKS ДО создания конфига
socksport=$((proxyport + 1))

# Конфигурация
cat > /etc/3proxy/3proxy.cfg <<EOF
flush

nscache 65536

auth strong

users user:CL:password
users unlimiteduser:CL:password
users limiteduser:CL:password

allow *

proxy -p$proxyport -a -n
socks -p$socksport -n

nobandlimin unlimiteduser * * * *
bandlimin 15728640 limiteduser
EOF

chmod 600 /etc/3proxy/3proxy.cfg

echo "3proxy ${VERSION} установлен и сконфигурирован"

# Создаём systemd-юнит
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/etc/3proxy
ExecStart=/usr/local/bin/3proxy /etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Активируем и запускаем сервис
systemctl daemon-reload
systemctl enable 3proxy
systemctl start 3proxy
