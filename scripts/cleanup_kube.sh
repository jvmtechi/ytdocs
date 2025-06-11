#to cleanup kube cluster - snk
cleanup_kube_api_server (){

#validation, if kube API server already running?
kubectl  cluster-info 2>&1 >/dev/null
if [ $? -ne 0 ];then
echo "INFO: Kubernetes control plane NOT found , skipping cleanup_kube_api_server ..."

return 1
fi

kubectl  cluster-info
#kubectl delete all --all-namespaces --all
echo "INFO: Resetting Kubernetes cluster..."
kubeadm reset -f
echo "INFO: Cleanup of CNI configuration "
rm -rf /etc/cni/net.d

rm -rf $HOME/.kube

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
cleanup_kube_pkgs
#reboot
