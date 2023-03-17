# OKE with RDMA VFs

Below instructions are based on the image `oke-ubuntu-20.04-x86_64-kix-202303110447`.

### 1 - Deploy an OKE cluster with a CN pool
Use the Terraform template [oke.tf](https://github.com/OguzPastirmaci/oke-rdma/blob/main/oke.tf) to deploy a new cluster in KIX. It will have a regular node pool, and a CN pool with 2 nodes.

```sh
variable "config_file_profile" { type = string }
variable "home_region" { type = string }
variable "region" { type = string }
variable "tenancy_id" { type = string }
variable "compartment_id" { type = string }
variable "ssh_public_key_path" { type = string }

module "oke" {
  source = "github.com/oracle-terraform-modules/terraform-oci-oke.git?ref=5.x-dev&depth=1"

  # Provider
  providers           = { oci.home = oci.home }
  config_file_profile = var.config_file_profile
  home_region         = var.home_region
  region              = var.region
  tenancy_id          = var.tenancy_id
  compartment_id      = var.compartment_id
  ssh_public_key_path = var.ssh_public_key_path

  # Resource creation
  assign_dns           = true  # *true/false
  create_vcn           = true  # *true/false
  create_bastion       = true  # *true/false
  create_cluster       = true  # *true/false
  create_operator      = false # *true/false
  create_iam_resources = false # true/*false
  use_defined_tags     = true  # true/*false

  allow_worker_ssh_access     = true
  control_plane_allowed_cidrs = ["0.0.0.0/0"]

  # Worker pool defaults
  worker_image_id         = "ocid1.image.oc1.ap-osaka-1.aaaaaaaaykfhzcj5uowhvwrdewdmzqxwq7k53f3ac2wvlb2tpaiujgbcesla"
  worker_image_os         = "Oracle Linux" # Ignored when worker_image_type = "custom"
  worker_image_os_version = "8"            # Ignored when worker_image_type = "custom"
  worker_image_type       = "custom"       # Must be "custom" when using an image OCID
  worker_shape            = { shape = "VM.Standard.E4.Flex", ocpus = 2, memory = 16, boot_volume_size = 50 }

  worker_pools = {
    np0 = {
      description = "OKE-managed Node Pool", enabled = true,
      mode        = "node-pool", size = 1,
    }
    cn0 = {
      description = "Self-managed Cluster Network", enabled = true,
      mode        = "cluster-network", size = 2, shape = "BM.GPU.B4.8", placement_ads = [1],
      secondary_vnics = {
        # storage0 = { nic_index = 0 } # Pending instance config limits increase for hpc_limited_availability
        storage1 = { nic_index = 1 }
      }
    }
  }
}

terraform {
  required_providers {
    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 4.67.3"
    }
  }

  required_version = ">= 1.2.0"
}

provider "oci" {
  config_file_profile = var.config_file_profile
  region              = var.region
  tenancy_ocid        = var.tenancy_id
}

provider "oci" {
  alias               = "home"
  config_file_profile = var.config_file_profile
  region              = var.home_region
  tenancy_ocid        = var.tenancy_id
}
```


### 2 - Wait until you see all nodes in the cluster

```sh
kubectl get nodes

NAME           STATUS     ROLES    AGE     VERSION
10.0.103.73    Ready      <none>   2d23h   v1.25.6
10.0.127.206   Ready      node     2d3h    v1.25.6
10.0.127.32    Ready      node     2d3h    v1.25.6
10.0.83.93     Ready      <none>   2d23h   v1.25.6
10.0.96.81     Ready      node     2d23h   v1.25.6
```

### 3 - Drain the GPU nodes
We will reboot the GPU nodes in the next steps, drain them before rebooting.

```sh
kubectl get nodes -l nvidia.com/gpu.present=true | awk '{if (NR!=1) {print $1}}' | xargs -I {} kubectl drain --ignore-daemonsets {}
```

### 4 - Install the GPU driver and Fabric Manager on the GPU nodes
Need to investigate: GPU Operator has an option to deploy the drivers as a container, but NCCL test results were drastically worse with the containerized driver option compared to GPU drivers installed on the host (179 GB/s vs 40 GB/s).

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

### 5 - Change MACAddressPolicy and reboot the hosts
The TF template will also deploy a bastion. Once all GPU nodes are up, use the bastion to SSH into the CN nodes and change `MACAddressPolicy=persistent` to `MACAddressPolicy=none` in `/usr/lib/systemd/network/99-default.link`, and reboot the nodes.

This is a fix needed until we have a new image. If you don't change it, VFs will get duplicate MAC addresses.

### 6 - Configure the VF interfaces
Once the GPU nodes are back, you will see VF interfaces named `rdma0v0..rdma15v0`.

`v0` ones are the VF interfaces. Create new IP configs for them in `/etc/network/interfaces.d` (pick some IPs that are not duplicate), and `ifup` the interfaces.

You should see IPs assigned to the VF interfaces now. Try pinging them from the other GPU node to make sure they work. It takes about 10 minutes for new VFs to authenticate after the previous step, and the reboot should give them enought time.

### 7 - Uncordon the GPU nodes

```sh
kubectl get nodes -l nvidia.com/gpu.present=true | awk '{if (NR!=1) {print $1}}' | xargs -I {} kubectl uncordon {}
```

### 8 - Add Helm repos for Network Operator and GPU Operator
```sh
helm repo add mellanox https://mellanox.github.io/network-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```
### 9 - Deploy SR-IOV CNI

Important: Do NOT use the manifest from the official SR-IOV CNI repo. Use the one here. You will get a permission issue if you use the official one.

`sriov-cni-daemonset.yaml`.

```yaml
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-sriov-cni-ds-amd64
  namespace: kube-system
  labels:
    tier: node
    app: sriov-cni
spec:
  selector:
    matchLabels:
      name: sriov-cni
  template:
    metadata:
      labels:
        name: sriov-cni
        tier: node
        app: sriov-cni
    spec:
      nodeSelector:
        kubernetes.io/arch: amd64
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      containers:
      - name: kube-sriov-cni
        image: ghcr.io/k8snetworkplumbingwg/sriov-cni
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: true
          privileged: true
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
          limits:
            cpu: "100m"
            memory: "50Mi"
        volumeMounts:
        - name: cnibin
          mountPath: /host/opt/cni/bin
      volumes:
        - name: cnibin
          hostPath:
            path: /opt/cni/bin
```            

```sh
kubectl apply -f sriov-cni-daemonset.yaml
```

### 10 - Deploy Network Operator

`network-operator-values.yaml`.

```yaml
deployCR: true

psp:
  enabled: false

ofedDriver:
  deploy: false

nvPeerDriver:
  deploy: false

nfd:
  enabled: true

rdmaSharedDevicePlugin:
  deploy: false

sriovNetworkOperator:
  enabled: false

sriovDevicePlugin:
  deploy: true
  resources:
      - name: rdma_sriov
        drivers: [mlx5_core]
        devices: [101a]
        isRdma: true
```      



```sh
helm install --wait \
  -n network-operator --create-namespace \
  -f network-operator-values.yaml \
  network-operator mellanox/network-operator
```

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.


### 11 - Create Network Attachment Definition

`network-attachment-definition.yaml`

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: sriov-net
  annotations:
    k8s.v1.cni.cncf.io/resourceName: nvidia.com/rdma_sriov
spec:
  config: |-
    {
      "cniVersion": "0.3.1",
      "name": "sriov-rdma-net",
      "plugins": [
        {
          "type": "sriov",
          "ipam": {
            "type": "whereabouts",
            "datastore": "kubernetes",
            "kubernetes": { "kubeconfig": "/etc/cni/net.d/whereabouts.d/whereabouts.kubeconfig" },
            "range": "192.168.0.0/16",
            "exclude": [],
            "log_file": "/var/log/whereabouts.log",
            "log_level": "info"
          }
        },
        { "type": "rdma" }
      ]
    }
```    

```sh
kubectl apply -f network-attachment-definition.yaml
```

### 12 - Deploy GPU Operator
```sh
helm install --wait \
-n gpu-operator --create-namespace \
gpu-operator nvidia/gpu-operator --version v22.9.2 \
--set driver.enabled=false --set nfd.enabled=false --set operator.defaultRuntime=crio --set driver.version="515.86.01" \
--set driver.rdma.enabled=true --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.

### 13 - Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
```

### 14 - Run NCCL test

Run the test with `kubectl apply -f nccl-test.yaml`.

`nccl-test.yaml`

```yaml
apiVersion: kubeflow.org/v2beta1
kind: MPIJob
metadata:
  name: nccl-test-a100
spec:
  slotsPerWorker: 8
  runPolicy:
    cleanPodPolicy: Running
  mpiReplicaSpecs:
    Launcher:
      replicas: 1
      template:
          spec:
            #initContainers:
            #- image: oguzpastirmaci/nccl-tests:cuda
            #  name: init
            #  command: ["sh", "-c", "sleep 5"]
            containers:
            - image: oguzpastirmaci/nccl-tests:cuda
              name: nccl
              env:
              - name: OMPI_ALLOW_RUN_AS_ROOT
                value: "1"
              - name: OMPI_ALLOW_RUN_AS_ROOT_CONFIRM
                value: "1"
              #command: ['sleep', '86400']
              command: ["/bin/bash", "-c"]
              args: ["mpirun \
                    --bind-to numa \
                    --mca pml ob1 --mca btl tcp,self --mca btl_tcp_if_include eth0 \
                    -x HCOLL_ENABLE_MCAST_ALL=0 \
                    -x coll_hcoll_enable=0 \
                    -x NCCL_DEBUG=WARN \
                    -x NCCL_IB_SL=0 \
                    -x NCCL_IB_TC=41 \
                    -x NCCL_IB_QPS_PER_CONNECTION=4 \
                    -x NCCL_IB_GID_INDEX=3 \
                    -x NCCL_IB_HCA=mlx5 \
                    /opt/nccl_tests/build/all_reduce_perf -b1G -e10G -i$((1024*1024*1024*9)) -g 1
                    "]

              resources:
                requests:
                  cpu: 2
                  memory: 128Mi
    Worker:
      replicas: 2
      template:
        metadata:
          annotations:
            k8s.v1.cni.cncf.io/networks: sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net, sriov-net
        spec:
          containers:
          - image: oguzpastirmaci/nccl-tests:cuda
            #securityContext:
              #capabilities:
                #add: [ "IPC_LOCK" ]
            name: nccl
            resources:
              requests:
                cpu: 100
                memory: 1500Gi
                nvidia.com/gpu: 8
                nvidia.com/rdma_sriov: 16
                #hugepages-2Mi: 1Gi
              limits:
                nvidia.com/gpu: 8
                nvidia.com/rdma_sriov: 16
                #hugepages-2Mi: 1Gi
```                

The initial pull of the container will take long. Wait until you see all pods' status as `Running`.

Run `kubectl logs -f $(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-a100,training.kubeflow.org/job-role=launcher -o name)` to get the logs from the launcher.

You might see an error message saying "ssh: Could not resolve hostname nccl-test-a100-worker-0.nccl-test-a100-worker.default.svc: Name or service not known", that's expected. Wait for 30 more seconds and run the previous command again. You will see the NCCL test results output.

```sh
kubectl logs -f $(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-a100,training.kubeflow.org/job-role=launcher -o name)

Warning: Permanently added 'nccl-test-a100-worker-0.nccl-test-a100-worker.default.svc,10.244.0.253' (ECDSA) to the list of known hosts.
Warning: Permanently added 'nccl-test-a100-worker-1.nccl-test-a100-worker.default.svc,10.244.1.9' (ECDSA) to the list of known hosts.
# nThread 1 nGpus 1 minBytes 1073741824 maxBytes 10737418240 step: 9663676416(bytes) warmup iters: 5 iters: 20 agg iters: 1 validation: 1 graph: 0
#
# Using devices
#  Rank  0 Group  0 Pid     17 on nccl-test-a100-worker-0 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  1 Group  0 Pid     18 on nccl-test-a100-worker-0 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank  2 Group  0 Pid     19 on nccl-test-a100-worker-0 device  2 [0x50] NVIDIA A100-SXM4-40GB
#  Rank  3 Group  0 Pid     20 on nccl-test-a100-worker-0 device  3 [0x53] NVIDIA A100-SXM4-40GB
#  Rank  4 Group  0 Pid     21 on nccl-test-a100-worker-0 device  4 [0x8c] NVIDIA A100-SXM4-40GB
#  Rank  5 Group  0 Pid     22 on nccl-test-a100-worker-0 device  5 [0x91] NVIDIA A100-SXM4-40GB
#  Rank  6 Group  0 Pid     23 on nccl-test-a100-worker-0 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank  7 Group  0 Pid     24 on nccl-test-a100-worker-0 device  7 [0xda] NVIDIA A100-SXM4-40GB
#  Rank  8 Group  0 Pid     17 on nccl-test-a100-worker-1 device  0 [0x0f] NVIDIA A100-SXM4-40GB
#  Rank  9 Group  0 Pid     18 on nccl-test-a100-worker-1 device  1 [0x15] NVIDIA A100-SXM4-40GB
#  Rank 10 Group  0 Pid     19 on nccl-test-a100-worker-1 device  2 [0x50] NVIDIA A100-SXM4-40GB
#  Rank 11 Group  0 Pid     20 on nccl-test-a100-worker-1 device  3 [0x53] NVIDIA A100-SXM4-40GB
#  Rank 12 Group  0 Pid     21 on nccl-test-a100-worker-1 device  4 [0x8c] NVIDIA A100-SXM4-40GB
#  Rank 13 Group  0 Pid     22 on nccl-test-a100-worker-1 device  5 [0x91] NVIDIA A100-SXM4-40GB
#  Rank 14 Group  0 Pid     23 on nccl-test-a100-worker-1 device  6 [0xd6] NVIDIA A100-SXM4-40GB
#  Rank 15 Group  0 Pid     24 on nccl-test-a100-worker-1 device  7 [0xda] NVIDIA A100-SXM4-40GB
NCCL version 2.14.3+cuda11.7
#
#                                                              out-of-place                       in-place          
#       size         count      type   redop    root     time   algbw   busbw #wrong     time   algbw   busbw #wrong
#        (B)    (elements)                               (us)  (GB/s)  (GB/s)            (us)  (GB/s)  (GB/s)       
  1073741824     268435456     float     sum      -1    11774   91.20  170.99      0    11774   91.19  170.99      0
 10737418240    2684354560     float     sum      -1   111812   96.03  180.06      0   111797   96.04  180.08      0
# Out of bounds values : 0 OK
# Avg bus bandwidth    : 175.531 
#
```

