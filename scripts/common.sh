#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail
# disable swap
sudo swapoff -a
# keeps the swap off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

VERSION="$(echo "${KUBERNETES_VERSION}" | grep -oE '[0-9]+\.[0-9]+')"
os_name=$(< /etc/os-release awk -F '=' '/^NAME/{print $2}' | awk '{print $1}' | tr -d '"')
# Variable Declaration
setup_ubuntu() {
    # DNS Setting
    if [ ! -d /etc/systemd/resolved.conf.d ]; then
        sudo mkdir /etc/systemd/resolved.conf.d/
    fi
    cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF
    sudo systemctl restart systemd-resolved
    # Install CRI-O Runtime
    OS_VERSION_ID=$(< /etc/os-release awk -F '=' '/^VERSION_ID/{print $2}' | tr -d '"')
    OS="xUbuntu_$OS_VERSION_ID"
    cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /
EOF
    cat <<EOF | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:"$VERSION".list
deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /
EOF

    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/"$VERSION"/"$OS"/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/"$OS"/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -

    sudo apt-get update
    sudo apt-get install cri-o cri-o-runc -y

    cat >> /etc/default/crio << EOF
${ENVIRONMENT}
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable crio --now

    echo "CRI runtime installed susccessfully"

    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update -y
    sudo apt-get install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
    sudo apt-get update -y
    sudo apt-get install -y jq
}
setup_centos() {
    # DNS Setting
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    MAIN_INTERFACE=$(ip route get 8.8.8.8 | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}')
    CONN_NAME=$(sudo nmcli -t -f NAME,DEVICE c s -a | grep "$MAIN_INTERFACE" | awk -F ':' '{print $1}')
    sudo nmcli con mod "$CONN_NAME" ipv4.dns "${DNS_SERVERS}"
    sudo nmcli connection reload
    sudo systemctl restart NetworkManager.service
    FIND_OS=$(< /etc/os-release awk -F '=' '/^NAME/{print $2}' | tr -d '"')
    # cat /etc/os-release | awk -F '=' '/^NAME/{print $2}' | awk '{print $1}' | tr -d '"'
    if [[ "$FIND_OS" == "CentOS Stream" ]]; then
        OS_VERSION_ID=$(< /etc/os-release awk -F '=' '/^VERSION_ID/{print $2}' | tr -d '"')
        if [[ "$OS_VERSION_ID" == "9" ]]; then
            CRIO_OS="CentOS_9_Stream"
        else
            CRIO_OS="CentOS_8_Stream"
        fi
    fi
    sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:"$VERSION".repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/"$VERSION"/"$CRIO_OS"/devel:kubic:libcontainers:stable:cri-o:"$VERSION".repo
    sudo yum -y update
    sudo yum -y install cri-o
    # sudo systemctl status crio
    sudo systemctl start crio
    sudo systemctl enable crio
    if [[ $(uname -m) == "aarch64" ]] || [[ $(uname -m) == "arm64" ]]; then
        curl -L --remote-name-all https://github.com/kubernetes-sigs/cri-tools/releases/download/v"$VERSION".0/crictl-v"$VERSION".0-linux-arm.tar.gz
        tar xzvf crictl-v"$VERSION".0-linux-arm.tar.gz
        chmod +x crictl
        sudo mv crictl /bin
        rm -rf crictl-v"$VERSION".0-linux-arm.tar.gz
    else
        curl -L --remote-name-all https://github.com/kubernetes-sigs/cri-tools/releases/download/v"$VERSION".0/crictl-v"$VERSION".0-linux-amd64.tar.gz
        tar xzvf crictl-v"$VERSION".0-linux-amd64.tar.gz
        chmod +x crictl
        sudo mv crictl /bin
        rm -rf crictl-v"$VERSION".0-linux-amd64.tar.gz
    fi
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

    sudo yum -y update
    sudo yum -y install kubeadm-"$KUBERNETES_VERSION" kubelet-"$KUBERNETES_VERSION" kubectl-"$KUBERNETES_VERSION" --disableexcludes=kubernetes
    sudo yum -y install jq
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
}

if [ "$os_name" == "Ubuntu" ]; then
    setup_ubuntu
elif [ "$os_name" == "CentOS" ]; then
    setup_centos
fi

local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "ens192" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
# sudo cat > /etc/default/kubelet << EOF
# KUBELET_EXTRA_ARGS=--node-ip=$local_ip
# ${ENVIRONMENT}
# EOF

cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
${ENVIRONMENT}
EOF

sudo systemctl enable kubelet.service