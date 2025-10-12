#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен быть запущен от root (sudo)"
    exit 1
fi

echo "===== Обновление пакетов и системы ====="
apt update && apt upgrade -y

echo "===== Установка необходимых пакетов ====="
INSTALL="vim git curl wget htop unzip tar file net-tools iputils-ping build-essential"
apt install -y $INSTALL
echo "===== Скрипт первоначальной настройки ====="

# Создание файла подкачки
if [[ $(cat /proc/swaps | wc -l) -le 1 ]]; then
    echo "===== Создание файла подкачки ====="
    read -p "Укажите размер файла подкачки (например, 2G, 512M): " swapfilesize
    if [[ -n "$swapfilesize" ]]; then
        fallocate -l "$swapfilesize" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        # Добавление в fstab (если еще нет)
        if ! grep -q "/swapfile" /etc/fstab; then
            echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        fi
        echo "Файл подкачки размером $swapfilesize успешно создан и активирован"
        swapon --show
    else
        echo "Ошибка: не указан размер файла подкачки"
        exit 1
    fi
else
    echo "Файл подкачки уже существует:"
    swapon --show
fi

# Смена пароля root
read -p "Сменить пароль для root пользователя? [y/N]: " input
if [[ "$input" == "y" || "$input" == "Y" ]]; then
    passwd
fi

# Новое имя хоста
read -p "Введите имя хоста: " newhostname
if [[ -z "$newhostname" ]]; then
    echo "Ошибка: имя хоста не может быть пустым."
    exit 1
fi

hostnamectl set-hostname "$newhostname"

# Создание нового пользователя
read -p "Введите имя нового пользователя: " newusername
if [[ -z "$newusername" ]]; then
    echo "Ошибка: имя пользователя не может быть пустым."
    exit 1
fi

adduser "$newusername"
usermod -aG sudo "$newusername"
echo "Пользователь $newusername создан и добавлен в группу sudo."

# Настройка SSH для нового пользователя
mkdir -p /home/"$newusername"/.ssh

echo "Введите публичный SSH-ключ для пользователя $newusername:"
read -r pubsshkey
echo "$pubsshkey" > /home/"$newusername"/.ssh/authorized_keys

chown -R "$newusername":"$newusername" /home/"$newusername"/.ssh
chmod 700 /home/"$newusername"/.ssh
chmod 600 /home/"$newusername"/.ssh/authorized_keys
echo "SSH-ключ установлен."

read -p "Введите SSH-порт: " sshport

# Резервная копия конфигурации SSH
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
echo "Резервная копия sshd_config создана: /etc/ssh/sshd_config.bak"

# Перезапись sshd_config с безопасными настройками
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

# Проверка синтаксиса и перезапуск SSH
sshd -t
systemctl restart ssh
echo "SSH конфигурация обновлена и SSH перезапущен."

echo "===== Конфигурация SSH ====="
cat /etc/ssh/sshd_config

#vim config
cat > /home/$newusername/.vimrc <<EOF
set nocompatible
syntax on
filetype plugin indent on
set number
set hidden
set ruler
set encoding=utf-8
set clipboard=unnamedplus
set clipboard=unnamed
EOF

echo "===== Конфигурация VIM ====="
cat /home/$newusername/.vimrc


mkdir -p /home/"$newusername"/.config

# Установка yazi
read -p "Установить файловый менеджер yazi? [y/N]: " input
if [[ "$input" == "y" || "$input" == "Y" ]]; then
    wget -qO yazi.zip https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip
    unzip -q yazi.zip -d yazi-temp
    mv yazi-temp/*/{ya,yazi} /usr/local/bin
    rm -rf yazi-temp yazi.zip
    yazi --version
    mkdir -p /home/"$newusername"/.config/yazi
    sudo chown -R "$newusername":"$newusername" /home/"$newusername"/.config/yazi
    cat > /home/"$newusername"/.config/yazi/yazi.toml <<EOF
[mgr]
show_hidden = true
ratio = [2, 4, 3]
[opener]
edit = [
    { run = 'vim "$@"', block = true, desc = "Vim" },
]
[open]
rules = [
    { mime = "text/*", use = "edit" },
]
EOF
fi

# Домашние директории
mkdir /home/"$newusername"/Documents

sudo chown -R "$newusername":"$newusername" /home/"$newusername"

echo "===== Проверка системы ====="
echo "1. Память:"
free -h
echo -e "\n2. Диски:"
df -h
echo -e "\n3. Загрузка:"
uptime
echo -e "\n4. Сеть:"
ip addr show
echo -e "\n5. Swap:"
swapon --show
echo -e "\n6. MyIp:"
curl https://api.myip.com

echo
