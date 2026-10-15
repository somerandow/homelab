helm repo add cilium https://helm.cilium.io/
helm template cilium cilium/cilium -f "$1" -n kube-system | kubectl apply -f -
