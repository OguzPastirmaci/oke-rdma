# oke-rdma


```sh
sudo apt install nvidia-headless-515-server
sudo apt install cuda-drivers-fabricmanager-515
sudo service nvidia-fabricmanager start
```

### MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```
