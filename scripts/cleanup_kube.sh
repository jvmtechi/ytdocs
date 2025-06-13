#to cleanup kube cluster - snk
cleanup_kube_api_server (){
REBOOT_FLAG=""
#validation, if kube API server already running?
kubectl  cluster-info 2>&1 >/dev/null
if [ $? -ne 0 ];then
echo "INFO: Kubernetes control plane NOT found , skipping cleanup_kube_api_server ..."

return 1
fi

kubectl  cluster-info
#kubectl delete all --all-namespaces --all
echo "INFO: deleting calico CNI..."
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml
#iptables -F
#iptables -t nat -F
ip route flush proto bird
ip link list | grep cali | awk '{print $2}' | cut -c 1-15 | xargs -I {} ip link delete {}
modprobe -r ipip
systemctl restart kubelet

echo "INFO: Resetting Kubernetes cluster..."
kubeadm reset -f
sleep 5
echo "INFO: Cleanup of CNI configuration "
rm -rf /etc/cni/net.d
rm -rf $HOME/.kube/config
REBOOT_FLAG=Y
}

#to cleanup kube pkgs - snk
cleanup_kube_pkgs (){

#validation, if pkg installed?
dpkg -l |grep kubeadm 2>&1 >/dev/null
if [ $? -ne 0 ];then
echo "INFO: Kubernetes packages NOT found, skipping cleanup_kube_pkgs ..."

return 1
fi

dpkg -l |grep -iE "kubeadm|kubelet|kubectl"

echo "INFO: uninstalling Kubernetes packages..."
apt-get purge -y kubeadm kubectl kubelet kubernetes-cni kube*
apt autoremove -y
rm -rf /etc/kubernetes
rm -rf /var/lib/etcd
rm -rf /var/lib/kubelet
echo "INFO: Removing Related Files and Directories "


rm -rf /etc/apt/sources.list.d/kubernetes.list
rm -rf /etc/apt/keyrings/kubernetes.gpg
rm -rf /etc/containerd/config.toml
rm -rf /etc/apt/trusted.gpg.d/containerd.gpg
rm -rf /etc/sysctl.d/kubernetes.conf
sysctl --system
sleep 5
rm -rf /etc/modules-load.d/kubernetes.conf

}
cleanup_kube_api_server

if [[ "$1" == "all" ]]; then
cleanup_kube_pkgs
echo "INFO: manual reboot recommended, before performing next kube setup !"
fi

if [[ "$REBOOT_FLAG" == "Y" ]]; then
echo "INFO: Rebooting nodes.. "
sleep 3
reboot
fi
