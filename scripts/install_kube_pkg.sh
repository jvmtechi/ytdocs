#!/bin/bash
####script for Kube pkgs install on Ubuntu server only

KUBE_PKG_VERSION=$1
INTERFACE_NAME=$2

S_TIME=2        #SLEEP time in sec during installation
K_TIMEOUT=60s  #kube pod wait time for ready
KUBE_API_IP=""
PKG_NAME=kubeadm  #sample pkg to test, whether kube already installed?

os=$(lsb_release -si)
if [[ "$os" != "Ubuntu" ]]; then
  echo "Ubuntu OS not detected!" && exit 1;
fi
#echo "installing Kube pkgs in $S_TIME sec(applicable for both Master and worker node)"
sleep $S_TIME

#define functions
#installing Kube pkgs for both Master and worker node

install_kube_pkgs (){

#validation, if pkg installed?
dpkg -l |grep $PKG_NAME  >/dev/null 2>&1
if [ $? -eq 0 ];then
echo "INFO: Kubernetes packages are already installed, skipping install_kube_pkgs ..."
dpkg -l |grep -iE "kubeadm|kubelet|kubectl"
return 1
fi

####
echo "##############################"
echo "will off swap and delete swap file too..."
sleep $S_TIME
#swap off
 swapoff -a
 free -h
 sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
 rm /swap.img  >/dev/null 2>&1
 echo "INFO: swap status after swap off "
 free -h
 sleep $S_TIME
#load k module
modprobe overlay
modprobe br_netfilter
sleep $S_TIME
#perm
echo "INFO: load module br_netfilter to file: /etc/modules-load.d/kubernetes.conf"
tee /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF
#kernel parameters like IP forwarding
echo "INFO: enabling IP forwarding and save to file: /etc/sysctl.d/kubernetes.conf"
tee /etc/sysctl.d/kubernetes.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT
sysctl --system
#Containerd provides the container run time for Kubernetes.
apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
sleep $S_TIME
#add containerd repository using following set of commands.
echo "INFO: Adding containerd repository to file: /etc/apt/trusted.gpg.d/containerd.gpg"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/containerd.gpg
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
#install containerd
echo "INFO: installing containerd packages"
apt update && sudo apt install containerd.io -y
#configure containerd so that it starts using SystemdCgroup.
echo ""
echo "INFO: configuring containerd to use SystemdCgroup in file: /etc/containerd/config.toml"
containerd config default |  tee /etc/containerd/config.toml >/dev/null 2>&1
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
#Restart containerd service so that above changes come into the affect.
 systemctl restart containerd

sleep $S_TIME
#Download the public signing key for the Kubernetes package repository using curl command // i choose 1.32 version
echo "INFO: Adding Kubernetes GPG 'keyrings' to File: /etc/apt/keyrings/kubernetes.gpg"
 curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBE_PKG_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes.gpg
#add the Kubernetes repository
echo "INFO: Adding Kubernetes 'repository' to File: /etc/apt/sources.list.d/kubernetes.list"
 echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBE_PKG_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
#Install Kubernetes components like Kubeadm, kubelet and kubectl,
echo "INFO: installing Kubernetes components ie. Kubeadm, kubelet and kubectl"
echo ""
apt update
apt install kubelet kubeadm kubectl -y
}

#to install kube cluster - snk
install_kube_api_server (){

#validation, if kube API server already running?
kubectl  cluster-info  >/dev/null 2>&1
if [ $? -eq 0 ];then
echo "INFO: Kubernetes control plane is already running , skipping install_kube_pkgs ..."
kubectl  cluster-info
return 1
fi

echo "##############################"
echo "INFO: Initializing Kubernetes API server using IP: $KUBE_API_IP"
echo "kubeadm init --apiserver-advertise-address=$KUBE_API_IP --pod-network-cidr=10.244.0.0/16"
kubeadm init --apiserver-advertise-address=$KUBE_API_IP --pod-network-cidr=10.244.0.0/16
sleep $S_TIME
echo "INFO: setup Kubernetes client access for user"
 mkdir -p $HOME/.kube
 cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
 chown $(id -u):$(id -g) $HOME/.kube/config
echo ""
echo "INFO: installing calico CNI plugin"
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml
sleep $S_TIME
echo "INFO: patching calico daemonset with hostonly NIC: $INTERFACE_NAME"
kubectl set env daemonset/calico-node  -n kube-system IP_AUTODETECTION_METHOD=interface=$INTERFACE_NAME

echo ""
echo "*****************************"
echo "INFO: waiting max $K_TIMEOUT  for a deployments(calico/coredns) to become available"
kubectl wait deployment -n kube-system calico-kube-controllers --for condition=Available=True --timeout=$K_TIMEOUT
kubectl wait deployment -n kube-system coredns  --for condition=Available=True --timeout=$K_TIMEOUT
master_node=$(kubectl get nodes -l node-role.kubernetes.io/control-plane= -o jsonpath='{.items[*].metadata.name}')
echo "INFO: Removing taint from master node: $master_node"
kubectl taint nodes $master_node  node-role.kubernetes.io/control-plane:NoSchedule-
systemctl restart kubelet
sleep $K_TIMEOUT

echo "*****************************"
echo "displaying node and pod status"
kubectl version
kubectl get no
kubectl get no -o wide
kubectl cluster-info
kubectl get po -A
echo "*****************************"
echo ""

}

if [[ -n "$KUBE_PKG_VERSION" &&  -n "$INTERFACE_NAME" && $# -eq 2 ]]; then
  echo "install kube  packages and configure API server.."
#192.168.56.67  enp0s8
KUBE_API_IP=$(ip addr show "$INTERFACE_NAME" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
echo  "Found $KUBE_API_IP address from INTERFACE : $INTERFACE_NAME for Kube API server config..."
echo "calling function install_kube_pkgs ..."
install_kube_pkgs
echo "##############################"
echo "calling function install_kube_api_server ..."
install_kube_api_server
elif [[ -n "$KUBE_PKG_VERSION" && $# -eq 1 ]];then
        if [[ "$KUBE_PKG_VERSION" =~ ^[1-9]\.[0-9][0-9]$ ]];then
                echo "KUBE target version: $KUBE_PKG_VERSION"
                echo "install kube pkg only"
                echo "calling function install_kube_pkgs ..."
                install_kube_pkgs
        else
        echo "usage: bash <script-name.sh> <kube-version ie 1.32> "
         exit 1;
        fi
else
  echo "usage: bash <script-name.sh> 1.33  enp0s8"
  echo "2 parameter needed!, 1st args kube version 1.32 or 1.33 .., 2nd args Inerface-name ie. enp0s8 for Kube API server config." && exit 1;
fi
