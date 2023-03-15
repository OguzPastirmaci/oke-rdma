# OKE with RDMA VFs

### GPU Driver
```sh
sudo apt install nvidia-headless-515-server
sudo apt install cuda-drivers-fabricmanager-515
sudo service nvidia-fabricmanager start
```

### Helm Repos
```sh
helm repo add mellanox https://mellanox.github.io/network-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Network Operator
```sh
helm install --wait \
  -n network-operator --create-namespace \
  -f network-operator-values.yaml \
  network-operator mellanox/network-operator
```

### SR-IOV CNI
```sh
kubectl apply -f sriov-cni-daemonset.yaml
```

### Network Attachment Definition
```sh
kubectl apply -f network-attachment-definition.yaml
```

### GPU Operator
```sh
helm install --wait --generate-name \                                                                         
     -n gpu-operator --create-namespace \
     nvidia/gpu-operator \
     --set driver.enabled=false --set nfd.enabled=false
```

### MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```
