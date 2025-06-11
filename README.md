#install Single node kuberntes using Script/ also cleanup
INSTALL using command-line-args
steps:
copy  scripts/install_kube_pkg.sh to your local
then chmod +x install_kube_pkg.sh
run the script with parameters
./install_kube_pkg.sh 1.32 enp0s8

CLEANUP
./cleanup_kube.sh
