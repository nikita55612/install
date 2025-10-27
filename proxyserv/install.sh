#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен быть запущен от root (sudo)"
    exit 1
fi

SetBBR() {
    grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    /usr/sbin/sysctl -p >/dev/null
}

touch install.log

apt update && apt upgrade -y

INSTALL="vim git curl wget vnstat ufw htop unzip tar file net-tools iputils-ping build-essential"
apt install -y $INSTALL

apt update && apt upgrade -y

timedatectl set-timezone Europe/Moscow

wget https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb
apt install ./fastfetch-linux-amd64.deb
rm fastfetch-linux-amd64.deb

if [[ $(cat /proc/swaps | wc -l) -le 1 ]]; then
    read -p "Укажите размер файла подкачки (например, 2G, 512M): " swapfilesize
    if [[ -n "$swapfilesize" ]]; then
        fallocate -l "$swapfilesize" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        fi
        swapon --show
    else
        echo "Ошибка: не указан размер файла подкачки"
        exit 1
    fi
else
    echo "Файл подкачки уже существует:"
    swapon --show
fi

SetBBR

read -p "Сменить пароль для root пользователя? [n/Y]: " input
if [[ "$input" == "y" || "$input" == "Y" ]]; then
    passwd
fi

read -p "Введите имя хоста: " newhostname
if [[ -z "$newhostname" ]]; then
    echo "Ошибка: имя хоста не может быть пустым."
    exit 1
fi

hostnamectl set-hostname "$newhostname"

read -p "Введите имя нового пользователя: " newusername
if [[ -z "$newusername" ]]; then
    echo "Ошибка: имя пользователя не может быть пустым."
    exit 1
fi

adduser "$newusername"
usermod -aG "$newusername"

mkdir -p /home/"$newusername"/.ssh

echo "Введите публичный SSH-ключ для пользователя $newusername:"
read -r pubsshkey
echo "$pubsshkey" > /home/"$newusername"/.ssh/authorized_keys

chown -R "$newusername":"$newusername" /home/"$newusername"/.ssh
chmod 700 /home/"$newusername"/.ssh
chmod 600 /home/"$newusername"/.ssh/authorized_keys

mkdir -p /home/"$newusername"/.config
mkdir /home/"$newusername"/Documents

touch openports.log

echo "=== UFW Firewall Setup ==="

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

read -p "Введите начальный порт: " startufwport
if ! [[ "$startufwport" =~ ^[0-9]+$ ]] || [ "$startufwport" -lt 1024 ] || [ "$startufwport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi
read -p "Введите конечный порт: " endufwport
if ! [[ "$endufwport" =~ ^[0-9]+$ ]] || [ "$endufwport" -lt 1024 ] || [ "$endufwport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

cat > openports.log <<EOF
=== UFW Firewall Setup ===
allow $startufwport:$endufwport/tcp
allow $startufwport:$endufwport/udp
EOF

ufw allow $startufwport:$endufwport/tcp
ufw allow $startufwport:$endufwport/udp

read -p "Введите SSH-порт: " sshport
if ! [[ "$sshport" =~ ^[0-9]+$ ]] || [ "$sshport" -lt 1024 ] || [ "$sshport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config <<EOF
Port $sshport
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PubkeyAuthentication yes
AuthorizedKeysFile %h/.ssh/authorized_keys
LoginGraceTime 30s
MaxAuthTries 3
MaxSessions 3
EOF

echo "SSH: $sshport" >> openports.log

sshd -t
systemctl restart ssh

ufw allow ssh
ufw --force enable

cat > /home/$newusername/.vimrc <<EOF
filetype plugin indent on
syntax on
set number
set relativenumber
set hidden
set expandtab
set shiftwidth=4
set softtabstop=4
set tabstop=4
set smartindent
set wrap
set lbr
set so=4
set backspace=indent,eol,start
set encoding=utf8
set noerrorbells
set novisualbell
set noswapfile
set clipboard=unnamedplus
EOF

read -p "Установить файловый менеджер yazi? [y/N]: " input
if [[ "$input" == "y" || "$input" == "Y" ]]; then
    wget -O yazi.zip https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip
    unzip yazi.zip -d yazi-temp
    mv yazi-temp/*/{ya,yazi} /usr/local/bin
    rm -rf yazi-temp yazi.zip
    mkdir -p /home/"$newusername"/.config/yazi
    cat > /home/"$newusername"/.config/yazi/yazi.toml <<EOF
[mgr]
show_hidden = true
ratio = [1, 2, 4]
[opener]
edit = [
    { run = 'vim "$@"', desc = "vim", block = true },
]
open = [
    { run = 'xdg-open "$1"', desc = "open", for = "linux" },
    { run = 'open "$@"', desc = "open", for = "macos" },
]
[open]
rules = [
	{ mime = "*/", use = "edit" },
    { mime = "text/*", use = "edit" },
	# { name = "*", use = "open" },
]
EOF
    chown -R "$newusername":"$newusername" /home/"$newusername"/.config/yazi
fi

goversion="1.25.3"
goarchive="go${goversion}.linux-amd64.tar.gz"

wget -c "https://go.dev/dl/${goarchive}" -O /tmp/$goarchive
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/$goarchive
rm -f /tmp/$goarchive

if ! grep -q '/usr/local/go/bin' "/root/.profile"; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "/root/.profile"
fi
if ! grep -q '/usr/local/go/bin' "/home/$newusername/.profile"; then
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "/home/$newusername/.profile"
fi

export PATH=$PATH:/usr/local/go/bin

serverip=$(curl -s -4 ifconfig.me)
if [[ -z "$serverip" ]]; then
    serverip=$(curl -s -6 ifconfig.me)
fi

if [[ -z "$serverip" ]]; then
    echo "Ошибка: Не удалось определить IP-адрес сервера"
    exit 1
fi

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root

read -p "Введите порт Xray [443]: " xrayport
xrayport=${xrayport:-443}

if ! [[ "$xrayport" =~ ^[0-9]+$ ]] || [ "$xrayport" -lt 1024 ] || [ "$xrayport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

read -p "Введите домен для Reality (SNI/dest) [github.com]: " xraydesthost
xraydesthost=${xraydesthost:-github.com}

read -p "Введите количество клиентов [1]: " xrayclicount
xrayclicount=${xrayclicount:-1}

if ! [[ "$xrayclicount" =~ ^[0-9]+$ ]]; then
    echo "Ошибка: Количество клиентов должно быть положительным числом"
    exit 1
fi

read -p "Введите базовое имя клиента [user]: " basexrayusername
basexrayusername=${basexrayusername:-user}

inboundsjson="["

xraylinkfile="./xraylinks"
> "$xraylinkfile"

currentxrayport=$xray_start_port

for ((i=0; i<xrayclicount; i++)); do
    xrayport=$currentxrayport
    xrayusername="${basexrayusername}$((i+1))"

    xrayuuid=$(xray uuid)
    xraykeys=$(xray x25519)
    xrayprivatekey=$(echo "$xraykeys" | awk '/PrivateKey:/ {print $2}')
    xraypublickey=$(echo "$xraykeys" | awk '/Password:/ {print $2}')
    xrayshortid=$(openssl rand -hex 8)

    inbound=$(cat <<EOF
    {
      "listen": "0.0.0.0",
      "port": $xrayport,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$xrayuuid",
            "email": "$xrayusername",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${xraydesthost}:443",
          "xver": 0,
          "show": false,
          "serverNames": ["${xraydesthost}", "www.${xraydesthost}"],
          "privateKey": "$xrayprivatekey",
          "shortIds": ["$xrayshortid"]
        }
      }
    }
EOF
)

    inboundsjson+="$inbound"
    [ $i -lt $((xrayclicount-1)) ] && inboundsjson+=","

    xraylink="vless://$xrayuuid@$serverip:$xrayport?security=reality&sni=$xraydesthost&pbk=$xraypublickey&sid=$xrayshortid&type=tcp&flow=xtls-rprx-vision&encryption=none#$xrayusername"

	echo "Xray: $xrayport" >> openports.log
    echo "$xraylink" >> "$xraylinkfile"

	currentxrayport=$((currentxrayport + 1))
done

inboundsjson+="]"

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "none"
  },
  "inbounds": $inboundsjson,
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

chmod 600 /usr/local/etc/xray/config.json

systemctl restart xray

systemctl status xray >> install.log

proxyversion=0.9.5

wget -q --show-progress --timeout=15 --tries=2 -O 3proxy.tar.gz \
  https://github.com/z3APA3A/3proxy/archive/${proxyversion}.tar.gz

tar -xzf 3proxy.tar.gz
mv 3proxy-${proxyversion} 3proxy
rm 3proxy.tar.gz

cd 3proxy
make -f Makefile.Linux
cd ..

mkdir -p /etc/3proxy /var/log/3proxy

if [ -f 3proxy/src/3proxy ]; then
    cp 3proxy/src/3proxy /usr/local/bin/
elif [ -f 3proxy/bin/3proxy ]; then
    cp 3proxy/bin/3proxy /usr/local/bin/
else
    echo "Бинарник 3proxy не найден после сборки"
    exit 1
fi

rm -rf 3proxy

read -p "Введите базовый порт для HTTP proxy (по умолчанию 44667): " httpproxyport
httpproxyport=${httpproxyport:-44667}

if ! [[ "$httpproxyport" =~ ^[0-9]+$ ]] || [ "$httpproxyport" -lt 1024 ] || [ "$httpproxyport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

read -p "Введите количество клиентов для HTTP proxy [1]: " proxyclicount
proxyclicount=${proxyclicount:-1}

if ! [[ "$proxyclicount" =~ ^[0-9]+$ ]] || [ "$proxyclicount" -lt 1 ]; then
    echo "Ошибка: Количество клиентов должно быть положительным числом"
    exit 1
fi

read -p "Введите базовый порт для SOCKS proxy (по умолчанию 44677): " socksproxyport
socksproxyport=${socksproxyport:-44677}

if ! [[ "$socksproxyport" =~ ^[0-9]+$ ]] || [ "$socksproxyport" -lt 1024 ] || [ "$socksproxyport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

read -p "Введите количество клиентов для SOCKS proxy [1]: " socksproxyclicount
socksproxyclicount=${socksproxyclicount:-1}

if ! [[ "$socksproxyclicount" =~ ^[0-9]+$ ]] || [ "$socksproxyclicount" -lt 1 ]; then
    echo "Ошибка: Количество клиентов должно быть положительным числом"
    exit 1
fi

read -p "Введите базовое имя клиента [user]: " baseproxyusername
baseproxyusername=${baseproxyusername:-user}

smartproxyserversfile="./smartproxyservers"
echo "[SmartProxy Servers]" > "$smartproxyserversfile"

proxylinkfile="./proxylinks"
> "$proxylinkfile"

proxycfgfile="/etc/3proxy/3proxy.cfg"
> "$proxycfgfile"

cat >> "$proxycfgfile" <<EOF
flush
nscache 65536
auth strong
EOF

for ((i=0; i<proxyclicount; i++)); do
    proxyport=$((httpproxyport + i))
    proxyusername="${baseproxyusername}$((i+1))"
    proxyuserpass=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)

    echo "users $proxyusername:CL:$proxyuserpass" >> "$proxycfgfile"
    cat >> "$proxycfgfile" <<EOF
allow $proxyusername
proxy -n -p$proxyport -a
flush
EOF

    echo "http://$proxyusername:$proxyuserpass@$serverip:$proxyport" >> "$proxylinkfile"
    echo "$serverip [HTTP] [proxy$((i+1))] [$socksusername] [$socksuserpass]" >> "$smartproxyserversfile"
    echo "HttpProxy: $proxyport" >> openports.log
done

for ((i=0; i<socksproxyclicount; i++)); do
    socksport=$((socksproxyport + i))
    socksusername="${baseproxyusername}$((i+1))"
    socksuserpass=$(openssl rand -base64 12 | tr -d '/+' | cut -c1-12)

    echo "users $socksusername:CL:$socksuserpass" >> "$proxycfgfile"
    cat >> "$proxycfgfile" <<EOF
allow $socksusername
socks -p$socksport
flush
EOF

    echo "socks5://$socksusername:$socksuserpass@$serverip:$socksport" >> "$proxylinkfile"
    echo "Socks5Proxy: $socksport" >> openports.log
done

chmod 600 /etc/3proxy/3proxy.cfg

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

systemctl daemon-reload
systemctl enable 3proxy
systemctl start 3proxy

systemctl status 3proxy >> install.log

wget https://raw.githubusercontent.com/nikita55612/install/main/proxyserv/servinfo.go

apt update && apt upgrade -y
chown -R "$newusername":"$newusername" /home/"$newusername"
chown -R "$newusername":"$newusername" /home/"$newusername"/.config

cat > servinfo.go <<EOF
package main

import (
	"flag"
	"fmt"
	"net/http"
	"os/exec"
	"strings"
	"sync/atomic"
	"time"
)

const DEFAULT_HOST = ""
const DEFAULT_PORT = 8090
var tsLast atomic.Int64
var infoCache = ""

func execCommand(name string, arg ...string) string {
	cmd := exec.Command(name, arg...)
	stdout, err := cmd.Output()
	if err != nil {
		fmt.Println(err.Error())
		return ""
	}
	return string(stdout)
}

func info(w http.ResponseWriter, req *http.Request) {
	tsNow := time.Now().Unix()
	if tsNow-tsLast.Load() <= 3 {
		fmt.Fprintf(w, infoCache)
		return
	}
	tsLast.Store(tsNow)
	infoCache = ""
	infoCache += strings.ReplaceAll(strings.ReplaceAll(execCommand("fastfetch", "--pipe", "--structure", "separator:os:separator:host:kernel:uptime:packages:shell:de:wm:wmtheme:theme:icons:font:cpu:gpu:memory:disk:localip"), "[34C", ""), "[31C", "")
	infoCache += execCommand("vnstat")
	infoCache += execCommand("vnstat", "-h")
	infoCache += execCommand("vnstat", "-hg")
	infoCache += execCommand("vnstat", "-5")
	fmt.Fprintf(w, infoCache)

}

func main() {
	host := flag.String("host", DEFAULT_HOST, "host 0.0.0.0")
	port := flag.Int("port", DEFAULT_PORT, "port 8090")
	flag.Parse()
	http.HandleFunc("/info", info)
	addr := fmt.Sprintf("%s:%d", *host, *port)
	fmt.Printf("http://%s/info\n", addr)
	http.ListenAndServe(addr, nil)
}
EOF

go build -o /usr/local/bin/servinfo servinfo.go

read -p "Введите порт для servinfo: " servinfoport

if ! [[ "$servinfoport" =~ ^[0-9]+$ ]] || [ "$servinfoport" -lt 1024 ] || [ "$servinfoport" -gt 65535 ]; then
    echo "Ошибка: Порт должен быть числом от 1024 до 65535"
    exit 1
fi

echo "servinfo: $servinfoport" >> openports.log

cat > /etc/systemd/system/servinfo.service <<EOF
[Unit]
Description=servinfoapp
After=network.target

[Service]
ExecStart=/usr/local/bin/servinfo -host=0.0.0.0 -port=$servinfoport
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable servinfo.service
systemctl start servinfo.service

systemctl status servinfo.service >> install.log

cat >> install.log <<EOF
Smart Proxy file $smartproxyserversfile:
$(cat "$smartproxyserversfile")

Ссылки для подключения proxy сохранены в $proxylinkfile:
$(cat "$proxylinkfile")

Ссылки для подключения xray сохранены в $xraylinkfile:
$(cat "$xraylinkfile")

servinfo.service: http://$serverip:$servinfoport/info
EOF

echo ""
cat install.log
