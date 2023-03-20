ARG CUDA_VERSION_MINOR=11.7.1
ARG BASE_IMAGE=nvidia/cuda:${CUDA_VERSION_MINOR}-cudnn8-devel-ubuntu20.04
FROM ${BASE_IMAGE}

ARG CUDA_VERSION_MAJOR=11.7
ARG TARGET_NCCL_VERSION=2.14.3-1

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -qq update && \
        apt-get -qq install -y --allow-change-held-packages --no-install-recommends \
        build-essential libtool autoconf automake autotools-dev unzip \
        ca-certificates \
        wget curl openssh-server vim environment-modules \
        iputils-ping net-tools \
        libnuma1 libsubunit0 libpci-dev \
        libpmix-dev \
        datacenter-gpu-manager \
        libnccl2=$TARGET_NCCL_VERSION+cuda${CUDA_VERSION_MAJOR} libnccl-dev=${TARGET_NCCL_VERSION}+cuda${CUDA_VERSION_MAJOR}

RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    ibverbs-utils libibverbs-dev libibumad3 libibumad-dev librdmacm-dev rdmacm-utils infiniband-diags ibverbs-utils \
    && rm -rf /var/lib/apt/lists/*

# HPC-X 2.14.0
RUN cd /tmp && \
wget -q -O - https://www.mellanox.com/downloads/hpc/hpc-x/v2.14/hpcx-v2.14-gcc-MLNX_OFED_LINUX-5-ubuntu20.04-cuda11-gdrcopy2-nccl2.16-x86_64.tbz | tar xjf - && \
    mv hpcx-v2.14-gcc-MLNX_OFED_LINUX-5-ubuntu20.04-cuda11-gdrcopy2-nccl2.16-x86_64 /opt/hpcx

ENV HPCX_DIR=/opt/hpcx
ENV HPCX_UCX_DIR=/opt/hpcx/ucx
ENV HPCX_UCC_DIR=/opt/hpcx/ucc
ENV HPCX_SHARP_DIR=/opt/hpcx/sharp
ENV HPCX_NCCL_RDMA_SHARP_PLUGIN_DIR=/opt/hpcx/nccl_rdma_sharp_plugin
ENV HPCX_HCOLL_DIR=/opt/hpcx/hcoll
ENV HPCX_MPI_DIR=/opt/hpcx/ompi
ENV HPCX_OSHMEM_DIR=/opt/hpcx/ompi
ENV HPCX_MPI_TESTS_DIR=/opt/hpcx/ompi/tests
ENV HPCX_OSU_DIR=/opt/hpcx/ompi/tests/osu-micro-benchmarks-5.8
ENV HPCX_OSU_CUDA_DIR=/opt/hpcx/ompi/tests/osu-micro-benchmarks-5.8-cuda
ENV HPCX_IPM_DIR=/opt/hpcx/ompi/tests/ipm-2.0.6
ENV HPCX_CLUSTERKIT_DIR=/opt/hpcx/clusterkit
ENV OMPI_HOME=/opt/hpcx/ompi
ENV MPI_HOME=/opt/hpcx/ompi
ENV OSHMEM_HOME=/opt/hpcx/ompi
ENV OPAL_PREFIX=/opt/hpcx/ompi
ENV OLD_PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PATH=/opt/hpcx/clusterkit/bin:/opt/hpcx/hcoll/bin:/opt/hpcx/ucc/bin:/opt/hpcx/ucx/bin:/opt/hpcx/ompi/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV OLD_LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64
ENV LD_LIBRARY_PATH=/opt/hpcx/nccl_rdma_sharp_plugin/lib:/opt/hpcx/ucc/lib/ucc:/opt/hpcx/ucc/lib:/opt/hpcx/ucx/lib/ucx:/opt/hpcx/ucx/lib:/opt/hpcx/sharp/lib:/opt/hpcx/hcoll/lib:/opt/hpcx/ompi/lib:/usr/local/nvidia/lib:/usr/local/nvidia/lib64
ENV OLD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs
ENV LIBRARY_PATH=/opt/hpcx/nccl_rdma_sharp_plugin/lib:/opt/hpcx/ompi/lib:/opt/hpcx/sharp/lib:/opt/hpcx/ucc/lib:/opt/hpcx/ucx/lib:/opt/hpcx/hcoll/lib:/opt/hpcx/ompi/lib:/usr/local/cuda/lib64/stubs
ENV OLD_CPATH=
ENV CPATH=/opt/hpcx/ompi/include:/opt/hpcx/ucc/include:/opt/hpcx/ucx/include:/opt/hpcx/sharp/include:/opt/hpcx/hcoll/include:
ENV PKG_CONFIG_PATH=/opt/hpcx/hcoll/lib/pkgconfig:/opt/hpcx/sharp/lib/pkgconfig:/opt/hpcx/ucx/lib/pkgconfig:/opt/hpcx/ompi/lib/pkgconfig:

# Build NCCL tests
ENV NCCL_TESTS_COMMITISH=2cbb968
WORKDIR /opt/nccl-tests
RUN  wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/${NCCL_TESTS_COMMITISH}.tar.gz | tar --strip-components=1 -xzf - \
   && make MPI=1 \
   && ln -s /opt/nccl-tests /opt/nccl_tests

RUN ldconfig

# Configure SSH
RUN sed -i 's/[ #]\(.*StrictHostKeyChecking \).*/ \1no/g' /etc/ssh/ssh_config && \
    echo "    UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config && \
    sed -i 's/#\(StrictModes \).*/\1no/g' /etc/ssh/sshd_config && \
    mkdir /var/run/sshd -p
