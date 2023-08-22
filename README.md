# OKE with RDMA VFs using GPU Operator and Network Operator

This guide has the instructions for deploying an OKE cluster using A100 BM nodes with RDMA connectivity enabled.

You will need at least 2 worker pools. You will also need to use the correct OS images.

- A worker pool for running non-GPU pods. This pool can use any Oracle Linux 7 image with the Red Hat Compatible Kernel (RHCK). You can find the import link below. If you want to use your own image, you can find the instructions [here](https://github.com/OguzPastirmaci/misc/blob/master/change-ol-kernel-to-rhck.md) on how to change the kernel to RHCK.

- A GPU worker pool for running GPU/RDMA pods. This pool requires you to use an image provided by the Oracle HPC team, you can find the import link below. This image included the OFED drivers and necessary packages configured for RDMA.

You can import the following images to your tenancy and use them.

#### Non-GPU nodes
[RHCK-Oracle-Linux-7.9-2023.06.30-1-OKE-1.26.2-632](https://objectstorage.ap-osaka-1.oraclecloud.com/p/V2sD4Ckur6NfIHCga92zKpaPfDvCgyACHGQiUjf_fs6H2SQTmna1a-NI1bOMhRvN/n/hpc_limited_availability/b/oke-images/o/RHCK-Oracle-Linux-7.9-2023.06.30-1-OKE-1.26.2-632)

#### GPU nodes
[OracleLinux-7-RHCK-3.10.0-OFED-5.4-3.6.8.1-OKE-1.26.2-2023.07.14-2](https://objectstorage.ap-osaka-1.oraclecloud.com/p/2vF_fbV3IQbd4oUTbpUSSq605MNsuepd1WyUBF9TKQgw4m3rbi5WErjebdbdngSP/n/hpc_limited_availability/b/oke-images/o/OracleLinux-7-RHCK-3.10.0-OFED-5.4-3.6.8.1-OKE-1.26.2-2023.07.14-2)

### Deploy the cluster using the Terraform template
You can find the template in the [terraform directory](./terraform/).

Make sure to update the image IDs in the `worker pools` block.

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

### Deploy the OCI RDMA Health Check daemonset
Deploying this daemonset is important. When a new node joins to the OKE cluster, it will report itself as ready. However, the RDMA network configuration of the nodes usually takes longer than the node joining the cluster. The health check daemonset checks the status of the RDMA interfaces, and removes the `oci.oraclecloud.com/oci-rdma-health-check` that is being added via cloud init.

```
kubectl apply -f https://raw.githubusercontent.com/OguzPastirmaci/oke-rdma/main/oci-rdma-health-check-ds.yaml
```

### Build the GPU Operator driver container image for Oracle Linux
You can follow the instructions [here](./building-gpu-operator-driver-image.md) for building the GPU Operator driver container image.

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

### Deploy GPU Operator
Use the container image you built in the `Build the GPU Operator driver container image for Oracle Linux` step above.

Change the `driver.repository` and `driver.version` in the Helm command below.

```sh
helm install --wait \
  -n gpu-operator --create-namespace \
  gpu-operator nvidia/gpu-operator \
  --version v23.3.2 \
  --set operator.defaultRuntime=crio \
  --set driver.repository=<The repository that you pushed your image> \
  --set driver.version=<The driver version in your pushed image. Only the version, don't add ol7.9 at the end> \
  --set toolkit.version=v1.13.5-centos7 \
  --set driver.rdma.enabled=true \
  --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.


### Deploy Network Operator

```
helm install --wait \
  -n network-operator --create-namespace \
  network-operator nvidia/network-operator \
  --version v23.5.0 \
  --set deployCR=true \
  --set nfd.enabled=false \
  --set rdmaSharedDevicePlugin.deploy=false \
  --set nvPeerDriver.deploy=true \
  --set sriovDevicePlugin.deploy=true \
  --set-json sriovDevicePlugin.resources='[{"name": "sriov_rdma_vf", "drivers": ["mlx5_core"], "devices": ["101a"], "isRdma": [true]}]'
```

Wait until all network operator pods are running with `kubectl get pods -n network-operator`.

### Create Network Attachment Definition

```sh
kubectl apply -f https://raw.githubusercontent.com/OguzPastirmaci/oke-rdma/main/network-attachment-definition.yaml
```

### Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/v0.4.0/deploy/v2beta1/mpi-operator.yaml
```

### Run NCCL test

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
            initContainers:
            - name: node-ordering-by-rack
              image: oguzpastirmaci/node-ordering-by-rack:init-mpijob-v1
              volumeMounts:
              - name: node-ordering-by-rack
                mountPath: "/node-ordering-by-rack"
              - name: mpi-job-config
                mountPath: /etc/mpi
              - name: ssh-auth
                mountPath: /root/.ssh
            volumes:
            - name: node-ordering-by-rack
              emptyDir: {}    
            containers:
            - image: oguzpastirmaci/nccl-tests:cuda-11.7.1
              name: nccl-tests
              volumeMounts:
              - name: node-ordering-by-rack
                mountPath: "/node-ordering-by-rack"
              env:
              - name: OMPI_ALLOW_RUN_AS_ROOT
                value: "1"
              - name: OMPI_ALLOW_RUN_AS_ROOT_CONFIRM
                value: "1"           
              #command: ['sleep', '86400']
              command: ["/bin/bash", "-c"]
              args: ["mpirun \
                    --bind-to numa \
                    --hostfile /node-ordering-by-rack/ordered_hostfile \
                    --mca pml ob1 --mca btl tcp,self --mca btl_tcp_if_include eth0  --mca coll ^hcoll \
                    -x HCOLL_ENABLE_MCAST_ALL=0 \
                    -x coll_hcoll_enable=0 \
                    -x NCCL_IB_HCA=mlx5 \
                    -x NCCL_IB_GID_INDEX=3 \
                    -x NCCL_IB_QPS_PER_CONNECTION=4 \
                    -x NCCL_IB_TC=41 \
                    -x NCCL_IB_SL=0 \
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
          - image: oguzpastirmaci/nccl-tests:cuda-11.7.1
            securityContext:
              capabilities:
                add: [ "IPC_LOCK" ]
            name: nccl
            resources:
              requests:
                cpu: 100
                memory: 750Gi
                nvidia.com/gpu: 8
                nvidia.com/sriov_rdma_vf: 16
              limits:
                nvidia.com/gpu: 8
                nvidia.com/sriov_rdma_vf: 16
            volumeMounts:
              - mountPath: /dev/shm
                name: dshm
          volumes:
            - emptyDir:
                medium: Memory
              name: dshm                
```                

The initial pull of the container will take long.

The init container will wait until all worker pods are running. You can check the logs of the init container by running:

```sh
kubectl logs -f $(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-a100,training.kubeflow.org/job-role=launcher -o name) -c node-ordering-by-rack
```

```sh
Mon Mar 20 20:19:04 UTC 2023 -- Waiting for all worker pods to be ready
...
Mon Mar 20 20:19:59 UTC 2023 -- Waiting for all worker pods to be ready
Mon Mar 20 20:20:04 UTC 2023 -- Waiting for all worker pods to be ready
Mon Mar 20 20:20:05 UTC 2023 -- All worker pods are ready
```

Once the init container has finished running, you can check the results of the NCCL test by running:

```sh
kubectl logs -f $(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-a100,training.kubeflow.org/job-role=launcher -o name)
```

```sh
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

