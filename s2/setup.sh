#!/usr/bin/env bash

CONTAINERD_VERSION="1.6.8-1"
DOCKER_VERSION="5:20.10.17~3-0~debian-$(lsb_release -cs)"
K8S_VERSION="1.23.10-00"

MYIFACE="eth1"
MYIP="$( ip -4 addr show ${MYIFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' )"

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
Acquire::ftp::proxy "ftp://${PLABS_PROXY}:${PLABS_PORT}/";
EOF
}


# # #


# Configure proxy if running on PracticeLabs
if nc -w3 -z ${PLABS_PROXY} ${PLABS_PORT}; then
  setproxy
fi

# Basic package installation
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

# Prepare SSH inter-VM communication
mv /home/vagrant/ssh/* /home/vagrant/.ssh
rm -r /home/vagrant/ssh
cat /home/vagrant/.ssh/tmpkey.pub >> /home/vagrant/.ssh/authorized_keys
cat << EOF >> /home/vagrant/.ssh/config
Host s2-*
   StrictHostKeyChecking no
   UserKnownHostsFile=/dev/null
EOF
chown vagrant. /home/vagrant/.ssh/config
chmod 600 /home/vagrant/.ssh/config /home/vagrant/.ssh/tmpkey

# Setup /etc/hosts
cat << EOF >> /etc/hosts
192.168.68.20 s2-master-1
192.168.68.25 s2-node-1
EOF

# Install Docker
apt install -y apt-transport-https \
               ca-certificates     \
               curl                \
               gnupg               \
               lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y containerd.io=${CONTAINERD_VERSION} \
               docker-ce=${DOCKER_VERSION}      \
               docker-ce-cli=${DOCKER_VERSION}
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "log-opts": {
    "max-size": "100m"
  }
}
EOF

# Enable and configure required modules
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl restart docker
systemctl enable docker

# Enable bridged traffic through iptables
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

# Configure containerd
mkdir -p /etc/containerd
containerd config default | \
  sed 's/^\([[:space:]]*SystemdCgroup = \).*/\1true/' | \
  tee /etc/containerd/config.toml

# Disable swap
swapoff -a
sed -i 's/^\(.*vg-swap.*\)/#\1/' /etc/fstab

# Install kubeadm and friends
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
apt update
apt install -y kubelet=${K8S_VERSION} \
               kubeadm=${K8S_VERSION} \
               kubectl=${K8S_VERSION}
apt-mark hold kubelet \
              kubeadm \
              kubectl

# Set correct IP address for kubelet
echo "KUBELET_EXTRA_ARGS=--node-ip=${MYIP}" >> /etc/default/kubelet
systemctl restart kubelet

# Configure kubectl autocompletion
kubectl completion bash > /etc/bash_completion.d/kubectl
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc

if [ "$1" == "master" ]; then
  # Initialize cluster
  kubeadm config images pull
  kubeadm init --apiserver-advertise-address=${MYIP} --apiserver-cert-extra-sans=${MYIP} --node-name="$( hostname )" --pod-network-cidr=10.32.0.0/12 --ignore-preflight-errors="all"

  # Configure kubectl
  mkdir -p $HOME/.kube
  cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config

  # Install Flannel CNI plugin
  #kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

  # Install Weave-net CNI plugin
  kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"

  # Create kubeadm join token
  kubeadm token create --print-join-command > /opt/join_token

  # Copy exercise scripts, set permissions
  mv /home/vagrant/scripts/* /usr/local/bin
  rm -r /home/vagrant/scripts
  chown root. /usr/local/bin/*
  chmod +x /usr/local/bin/*
else
  # Copy join token and enter cluster
  sudo -u vagrant scp -i /home/vagrant/.ssh/tmpkey vagrant@s2-master-1:/opt/join_token /tmp
  sh /tmp/join_token
  rm -f /tmp/join_token
fi
