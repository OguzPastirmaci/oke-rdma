**Important note:** You will need an image that does not have the GPU driver pre-installed for the steps below. If you already have the GPU driver installed on the nodes, the deployment will fail because of how the GPU Operator is designed to work.

### Change ID and VERSION_ID values in /etc/os-release

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
