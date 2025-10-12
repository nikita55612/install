#!/bin/bash

install_tools () {
    tools="sudo man-db vim git curl wget htop unzip tar file net-tools iputils-ping build-essential"
    sudo apt install $tools -y
}

set_vim_config () {
    sudo apt install vim -y
    cat config/vim > ~/.vimrc
}

install_yazi () {
    wget -qO yazi.zip https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip
    unzip -q yazi.zip -d yazi-temp
    mv yazi-temp/*/{ya,yazi} /usr/local/bin
    rm -rf yazi-temp yazi.zip
    mkdir -p ~/.config/yazi/
    cat config/yazi > ~/.config/yazi/yazi.toml
}

install_x () {
    sudo apt install xorg -y
    sudo apt update
}

install_chrome () {

}

sudo apt update && sudo apt upgrade
