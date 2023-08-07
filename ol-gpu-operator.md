**Important note:** You will need an Oracle Linux 7 image that does not have the GPU driver pre-installed for the steps below. If you already have the GPU driver installed on the nodes, the deployment will fail because of how the GPU Operator is designed to work.

You also need to use an OS image that has the Red Hat Compatible (RHCK) kernel.

You can import the image [from this link](https://objectstorage.us-phoenix-1.oraclecloud.com/p/ZDHMTkZfJUNzrJrJ9o8pedJ1dwlBzH2GaUqvuKL9xMrDhV_Y_AHn-pLI9YuzZ-my/n/hpc_limited_availability/b/oke-images/o/RHCK-Oracle-Linux-7.9-2023.05.24-0-OKE-1.26.2-625) as an example.

This is the `Oracle-Linux-7.9-2023.05.24-0-OKE-1.26.2-625` image [here](https://docs.oracle.com/en-us/iaas/images/image/9042e7ef-606b-4ab5-b83b-d811963f193e/), the only difference is that the above image has RHCK kernel instead of UEK.


### Change ID and VERSION_ID values in /etc/os-release on all nodes in the cluster (or to be more precise, on the nodes that NFD pods will be running)

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

You can choose any driver version in the below command (`--set driver.version`) for the GPU Operator version (`--version`) listed [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html#gpu-operator-component-matrix) for the GPU Operator release.

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
