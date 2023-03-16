# OKE with RDMA VFs

### Install GPU Driver to the hosts
```sh
sudo apt install nvidia-headless-515-server -y
sudo apt install cuda-drivers-fabricmanager-515 -y
sudo service nvidia-fabricmanager start
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
gpu-operator nvidia/gpu-operator \
--set driver.enabled=false --set nfd.enabled=false
```

### Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```
