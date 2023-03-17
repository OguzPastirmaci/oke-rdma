# OKE with RDMA VFs

### Change MACAddressPolicy and reboot the hosts

```sh
/usr/lib/systemd/network/99-default.link

MACAddressPolicy=none
```

### Install Fabric Manager to the hosts
```sh
sudo apt install nvidia-fabricmanager-515 -y
sudo systemctl --now enable nvidia-fabricmanager
```

### Add Helm repos
```sh
helm repo add mellanox https://mellanox.github.io/network-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Deploy Network Operator
```sh
helm install --wait \
  -n network-operator --create-namespace \
  -f network-operator-values.yaml \
  network-operator mellanox/network-operator
```

### Deploy SR-IOV CNI
```sh
kubectl apply -f sriov-cni-daemonset.yaml
```

### Create Network Attachment Definition
```sh
kubectl apply -f network-attachment-definition.yaml
```

### Deploy GPU Operator
```sh
helm install --wait \
-n gpu-operator --create-namespace \
-f gpu-operator-values.yaml \
gpu-operator nvidia/gpu-operator --version v22.9.2
```

### Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```
