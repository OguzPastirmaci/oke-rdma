**Important note:** You will need an Oracle Linux 7 image that does not have the GPU driver pre-installed for the steps below. If you already have the GPU driver installed on the nodes, the deployment will fail because of how the GPU Operator is designed to work.

You also need to use an OS image that has the Red Hat Compatible (RHCK) kernel.

You can import the image [from this link](https://objectstorage.us-phoenix-1.oraclecloud.com/p/ZDHMTkZfJUNzrJrJ9o8pedJ1dwlBzH2GaUqvuKL9xMrDhV_Y_AHn-pLI9YuzZ-my/n/hpc_limited_availability/b/oke-images/o/RHCK-Oracle-Linux-7.9-2023.05.24-0-OKE-1.26.2-625) as an example.

This is the `Oracle-Linux-7.9-2023.05.24-0-OKE-1.26.2-625` image [here](https://docs.oracle.com/en-us/iaas/images/image/9042e7ef-606b-4ab5-b83b-d811963f193e/), the only difference is that the above image has RHCK kernel instead of UEK.

### Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME           STATUS     ROLES    AGE     VERSION
10.0.103.73    Ready      <none>   2d23h   v1.25.6
10.0.127.206   Ready      node     2d3h    v1.25.6
10.0.127.32    Ready      node     2d3h    v1.25.6
10.0.83.93     Ready      <none>   2d23h   v1.25.6
10.0.96.81     Ready      node     2d23h   v1.25.6
```

### Get the latest Helm 3 version
```sh
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### Add Helm repos for Network Operator and GPU Operator
```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Change ID and VERSION_ID values in /etc/os-release on all nodes in the cluster (or to be more precise, on the nodes that NFD pods will be running)

You can do this from cloud-init or manually on the nodes. For testing purposes, you can change it on all nodes. There's an [open issue](https://github.com/NVIDIA/gpu-operator/issues/562) about this and it will be fixed in the next GPU Operator release so you won't need to edit the os-release file on non-GPU nodes.

```
sudo sed -i 's/ID="ol"/ID="centos"/g' /etc/os-release

sudo sed -i 's/VERSION_ID="7.9"/VERSION_ID="7"/g' /etc/os-release
```

### Save the following as a file

Make sure the extension of the file is repo (e.g. `ol7.repo`)

```
[ol7_latest]
name=Oracle Linux $releasever Latest ($basearch)
baseurl=https://yum.oracle.com/repo/OracleLinux/OL7/latest/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=0
enabled=1
```

### Create the gpu-operator namespace

```
kubectl create ns gpu-operator
```

### Create a Kubernetes configmap with the repo file from the previous step

```
kubectl create configmap repo-config -n gpu-operator --from-file=./ol7.repo
```

### Use the configmap you created with the GPU Operator deployment command

You can choose any driver version in the below command  with `--set driver.version` based on the GPU Operator version that you're deploying with `--version`listed [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html#gpu-operator-component-matrix).

For example for the 23.3.2 release, here are the GPU driver versions that you can use:
```
535.54.03
525.125.06
525.105.17
515.86.01
510.108.03
470.199.02
470.161.03
450.248.02
450.216.04
```
If you don't specify a version with `--set driver.version`, the default GPU driver version for the GPU Operator release will be deployed (e.g. `525.105.17` for GPU Operator `23.3.2`.

```
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v23.3.2 \
  --set operator.defaultRuntime=crio \
  --set driver.version=510.108.03 \
  --set toolkit.version=v1.13.5-centos7 \
  --set driver.repoConfig.configMapName=repo-config
```
