#!/usr/bin/env bash

CONTAINERD_VERSION="1.3.7-1"
DOCKER_VERSION="5:19.03.13~3-0~debian-$(lsb_release -cs)"
K8S_VERSION="1.19.2-00"

MYIFACE="eth1"
MYIP="$( ip -4 addr show ${MYIFACE} | grep -oP '(?<=inet\s)\d+(\.\d+){3}' )"

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
               gnupg-agent         \
               software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] \
                    https://download.docker.com/linux/debian \
                    $(lsb_release -cs) \
                    stable"
apt update
apt install -y containerd.io=${CONTAINERD_VERSION} \
               docker-ce=${DOCKER_VERSION}      \
               docker-ce-cli=${DOCKER_VERSION}
cat << EOF >> /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d
systemctl daemon-reload
systemctl restart docker
systemctl enable docker

# Enable bridged traffic through iptables
modprobe br_netfilter
cat << EOF >> /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# Disable swap
swapoff -a
sed -i 's/^\(.*vg-swap.*\)/#\1/' /etc/fstab

# Install kubeadm and friends
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat << EOF >> /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
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
  kubeadm init --apiserver-advertise-address=${MYIP} --apiserver-cert-extra-sans=${MYIP} --node-name "$( hostname )" --pod-network-cidr=10.244.0.0/16

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
