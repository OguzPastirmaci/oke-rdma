# OKE with RDMA VFs

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

### Remove the GPU taint from the nodes so the daemonsets can be scheduled
```sh
kubectl get nodes --show-labels |grep BM.GPU | awk '{print $1}' | xargs -I {} kubectl taint nodes {} nvidia.com/gpu=present:NoSchedule-
```

### Add Helm repos for Network Operator and GPU Operator
```sh
helm repo add mellanox https://mellanox.github.io/network-operator
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

### Deploy GPU Operator
```sh
helm install --wait \
-n gpu-operator --create-namespace \
gpu-operator nvidia/gpu-operator --version v23.3.1 \
--set operator.defaultRuntime=crio --set driver.version="510.108.03" \
--set driver.rdma.enabled=true --set driver.rdma.useHostMofed=true
```

Wait until all network operator pods are running with `kubectl get pods -n gpu-operator`.


### Deploy Network Operator

`network-operator-values.yaml`

```yaml
deployCR: true

psp:
  enabled: false

ofedDriver:
  deploy: false

nvPeerDriver:
  deploy: false

nfd:
  enabled: false

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

### Deploy SR-IOV CNI

```sh
kubectl apply -f https://raw.githubusercontent.com/openshift/sriov-cni/master/images/k8s-v1.16/sriov-cni-daemonset.yaml
```

### Deploy RDMA CNI

```sh
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/rdma-cni/master/deployment/rdma-cni-daemonset.yaml
```

### Create Network Attachment Definition

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


### Deploy MPI Operator
```sh
kubectl apply -f https://raw.githubusercontent.com/kubeflow/mpi-operator/master/deploy/v2beta1/mpi-operator.yaml
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
            - image: oguzpastirmaci/nccl-tests:cuda
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
          - image: oguzpastirmaci/nccl-tests:cuda
            #securityContext:
              #capabilities:
                #add: [ "IPC_LOCK" ]
            name: nccl
            resources:
              requests:
                cpu: 100
                memory: 750Gi
                nvidia.com/gpu: 8
                nvidia.com/rdma_sriov: 16
              limits:
                nvidia.com/gpu: 8
                nvidia.com/rdma_sriov: 16
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
kubectl logs -f  $(kubectl get pods -l training.kubeflow.org/job-name=nccl-test-a100,training.kubeflow.org/job-role=launcher -o name) -c node-ordering-by-rack

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

