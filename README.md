# OKE with RDMA VFs

### Deploy an OKE cluster with a CN pool
Use the Terraform template [oke.tf](https://github.com/OguzPastirmaci/oke-rdma/blob/main/oke.tf) to deploy a new cluster in KIX. It will have a regular node pool, and a CN pool with 2 nodes.

### Change MACAddressPolicy and reboot the hosts
The TF template will also deploy a bastion. Once all GPU nodes are up, use the bastion to SSH into the CN nodes and change `MACAddressPolicy=persistent` to `MACAddressPolicy=none` in `/usr/lib/systemd/network/99-default.link`, and reboot the nodes.

This is a fix needed until we have a new image. If you don't change it, VFs will get duplicate MAC addresses.

### Configure the VF interfaces
Once the GPU nodes are back, you will see VF interfaces named `rdma0v0..rdma15v0`.

`v0` ones are the VF interfaces. Create new IP configs for them in `/etc/network/interfaces.d` (pick some IPs that are not duplicate), and `ifup` the interfaces.

You should see IPs assigned to the VF interfaces now. Try pingning them from the other GPU node to make sure they work. It takes about 10 minutes for new VFs to authenticate after the previous step, and the reboot should give them enought time.

### Install Fabric Manager to the hosts
```sh
sudo apt install nvidia-fabricmanager-515 -y
sudo systemctl --now enable nvidia-fabricmanager
```

### Add Helm repos for Network Operator and GPU Operator
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

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.

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

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```
