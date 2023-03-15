# oke-rdma


```sh
sudo apt install nvidia-headless-515-server
sudo apt install cuda-drivers-fabricmanager-515
sudo service nvidia-fabricmanager start
```

### Network Operator
```sh
helm install --wait \
  -n network-operator --create-namespace \
  -f network-operator-values.yaml \
  network-operator mellanox/network-operator
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
