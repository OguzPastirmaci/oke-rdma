# OKE with RDMA VFs

### 1 - Deploy an OKE cluster with a CN pool
Use the Terraform template [oke.tf](https://github.com/OguzPastirmaci/oke-rdma/blob/main/oke.tf) to deploy a new cluster in KIX. It will have a regular node pool, and a CN pool with 2 nodes.

### 2 - Install the GPU driver and Fabric Manager on the GPU nodes
Needs more info: GPU Operator has an option to deploy the drivers as a container, but NCCL test results were drastically worse with the containerized driver option compared to GPU drivers installed on the host (179 GB/s vs 40 GB/s).

Install the drivers but do NOT reboot the nodes yet. You'll reboot them in the next step.

```sh
sudo apt-get install linux-headers-$(uname -r)
distribution=$(. /etc/os-release;echo $ID$VERSION_ID | sed -e 's/\.//g')
wget https://developer.download.nvidia.com/compute/cuda/repos/$distribution/x86_64/cuda-keyring_1.0-1_all.deb
sudo dpkg -i cuda-keyring_1.0-1_all.deb
sudo apt-get update

sudo apt-get install cuda-drivers-515=515.86.01-1 -y
sudo apt-get install cuda-drivers-fabricmanager-515=515.86.01-1 -y

sudo systemctl --now enable nvidia-fabricmanager
```

### 3 - Change MACAddressPolicy and reboot the hosts
The TF template will also deploy a bastion. Once all GPU nodes are up, use the bastion to SSH into the CN nodes and change `MACAddressPolicy=persistent` to `MACAddressPolicy=none` in `/usr/lib/systemd/network/99-default.link`, and reboot the nodes.

This is a fix needed until we have a new image. If you don't change it, VFs will get duplicate MAC addresses.

### 4 - Configure the VF interfaces
Once the GPU nodes are back, you will see VF interfaces named `rdma0v0..rdma15v0`.

`v0` ones are the VF interfaces. Create new IP configs for them in `/etc/network/interfaces.d` (pick some IPs that are not duplicate), and `ifup` the interfaces.

You should see IPs assigned to the VF interfaces now. Try pinging them from the other GPU node to make sure they work. It takes about 10 minutes for new VFs to authenticate after the previous step, and the reboot should give them enought time.

### 5 - Add Helm repos for Network Operator and GPU Operator
```sh
helm repo add mellanox https://mellanox.github.io/network-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### 6 - Deploy Network Operator
```sh
helm install --wait \
  -n network-operator --create-namespace \
  -f network-operator-values.yaml \
  network-operator mellanox/network-operator
```

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.

### 7 - Deploy SR-IOV CNI

Important: Do NOT use the manifest from the official SR-IOV CNI repo. Use the one in this repo. You will get a permission issue if you use the official one.

```sh
kubectl apply -f sriov-cni-daemonset.yaml
```

### 8 - Create Network Attachment Definition
```sh
kubectl apply -f network-attachment-definition.yaml
```

### 9 - Deploy GPU Operator
```sh
helm install --wait \
-n gpu-operator --create-namespace \
gpu-operator nvidia/gpu-operator --version v22.9.2 \
--set driver.enabled=false --set nfd.enabled=false --set operator.defaultRuntime=crio --set driver.version="515.86.01" \
--set driver.rdma.enabled=true --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### 10 - Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```

### 11 - Run NCCL test

Run the test with `kubectl apply -f nccl-test.yaml`.


