#!/usr/bin/bash

#--------------------------------------------------
# Update and upgrade the system
#--------------------------------------------------
echo "=== Updating system packages ... ==="
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y

# install necessary packages:
sudo apt install -y git nano wget apt-transport-https ca-certificates curl gnupg2 software-properties-common iptables-persistent lsb-release

#----------------------------------------------------
# Install Openssh server
#----------------------------------------------------
echo "=== Disabling password authentication ... ==="
sudo apt -y install openssh-server
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh

#--------------------------------------------------
# Setting up the timezones
#--------------------------------------------------
# set the correct timezone on ubuntu
timedatectl set-timezone Africa/Kigali
timedatectl

# Open the necessary ports on the CP's (control-plane node) firewall.
sudo apt install -y ufw 
sudo ufw allow 6443/tcp
sudo ufw allow 10250:10252/tcp 
sudo ufw allow 8472/udp
sudo ufw allow 2379:2380/tcp
sudo ufw allow 10259/tcp
sudo ufw allow 10257/tcp
sudo ufw reload
sudo ufw enable-y

# Get status
sudo ufw status

# check ip address assigned
ip a

sleep 10

# Assign static ip address
sudo nano /etc/network/interfaces

# Change hostname
sudo hostnamectl set-hostname k8s-master

# Change hosts
sudo tee /etc/hosts <<EOF
10.10.10.1 k8s-master
10.10.10.2 k8s-worker1
10.10.10.3 k8s-worker2
10.10.10.4 k8s-worker3
EOF

# Disable Swap
sudo swapoff -a
sudo sed -i 's/^swap/#swap/' /etc/fstab

# Always load on boot the k8s modules needed.
sudo tee /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Verify
sudo lsmod | grep -E 'netfilter|overlay'

# Enable network forwarding !
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system

# Add the Docker GPG Key and Repository
sudo mkdir -p /etc/apt/keyrings
sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

 # Add the repository to Apt sources:
 echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
 $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the system:
sudo apt update

# Install Docker Community Edition:
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
sudo systemctl start docker
sudo systemctl enable --now docker

# Install kubeadm
VERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
VERSION=${VERSION%.*}

curl -fsSL "https://pkgs.k8s.io/core:/stable:/${VERSION}/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# allow unprivileged APT programs to read this keyring
sudo chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# This overwrites any existing configuration in /etc/apt/sources.list.d/kubernetes.list
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# helps tools such as command-not-found to work correctly
sudo chmod 0644 /etc/apt/sources.list.d/kubernetes.list

sleep 1

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Get images
sudo kubeadm config images pull

# Init kubernetes
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Setup kubeconfig
KUBEDIR="$HOME/.kube"
rm -rf   "${KUBEDIR}"
mkdir -p "${KUBEDIR}"

sudo cp -i /etc/kubernetes/admin.conf "${KUBEDIR}/config"

sudo chown "$(id -u)":"$(id -g)" "${KUBEDIR}/config"

ls -la "${KUBEDIR}/config"

echo 'alias k="kubectl"' | sudo tee -a /etc/bash.bashrc
source /etc/bash.bashrc

# Verify
kubectl cluster-info
echo "Run: kubectl cluster-info dump"

kubectl get nodes   -o wide
kubectl get pods -A -o wide

# CNI Install: flannel
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Get k8s cluster join command for worker nodes.
echo ""
echo "Run this command to the workers node to join the cluster:"
sudo kubeadm token create --print-join-command
echo ""
echo ""
