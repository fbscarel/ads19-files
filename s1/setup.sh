#!/usr/bin/env bash

PLABS_PROXY="192.168.255.13"
PLABS_PORT="8080"


# # #


setproxy() {
cat << EOF > /etc/profile.d/proxy.sh
export http_proxy="http://${PLABS_PROXY}:${PLABS_PORT}/"
export HTTP_PROXY="http://${PLABS_PROXY}:${PLABS_PORT}/"
export https_proxy="http://${PLABS_PROXY}:${PLABS_PORT}/"
export HTTPS_PROXY="http://${PLABS_PROXY}:${PLABS_PORT}/"
export ftp_proxy="http://${PLABS_PROXY}:${PLABS_PORT}/"
export FTP_PROXY="http://${PLABS_PROXY}:${PLABS_PORT}/"
export no_proxy="127.0.0.1,localhost"
export NO_PROXY="127.0.0.1,localhost"
EOF
chmod +x /etc/profile.d/proxy.sh

cat << EOF > ~/.wgetrc
use_proxy = on
http_proxy = http://${PLABS_PROXY}:${PLABS_PORT}/ 
https_proxy = http://${PLABS_PROXY}:${PLABS_PORT}/ 
ftp_proxy = http://${PLABS_PROXY}:${PLABS_PORT}/
EOF

cat << EOF > /etc/apt/apt.conf.d/99proxy
Acquire::http::proxy "http://${PLABS_PROXY}:${PLABS_PORT}/";
Acquire::https::proxy "http://${PLABS_PROXY}:${PLABS_PORT}/";
Acquire::ftp::proxy "http://${PLABS_PROXY}:${PLABS_PORT}/";
EOF

mkdir -p /root/.docker
cat << EOF > /root/.docker/config.json
{
 "proxies": {
   "default":   {
     "httpProxy": "http://${PLABS_PROXY}:${PLABS_PORT}/",
     "httpsProxy": "http://${PLABS_PROXY}:${PLABS_PORT}/",
     "ftpProxy": "http://${PLABS_PROXY}:${PLABS_PORT}/",
     "noProxy": "localhost,127.0.0.0/8,192.168.68.0/24"
   }
 }
}
EOF
}


# # #


mv /home/vagrant/scripts/* /usr/local/bin
rm -r /home/vagrant/scripts

chown root. /usr/local/bin/*
chmod +x /usr/local/bin/*

if nc -w3 -z ${PLABS_PROXY} ${PLABS_PORT}; then
  setproxy
fi

apt update
apt install -y vim dos2unix
cat << EOF > /root/.vimrc
set nomodeline
set bg=dark
set tabstop=2
set expandtab
set ruler
set nu
syntax on
EOF
find /usr/local/bin -name lab-* | xargs dos2unix
