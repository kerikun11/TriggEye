# ==================== Building Model Layer ===========================
# This is a little trick to improve caching and minimize rebuild time
# and bandwidth. Note that RUN commands only cache-miss if the prior layers
# miss, or the dockerfile changes prior to this step.
# To update these patch files, be sure to run build with --no-cache
FROM alpine as model_data
RUN apk --no-cache --update-cache add curl
WORKDIR /data/patch_experts

RUN curl -fOL https://www.dropbox.com/s/7na5qsjzz8yfoer/cen_patches_0.25_of.dat \
    && curl -fOL https://www.dropbox.com/s/k7bj804cyiu474t/cen_patches_0.35_of.dat \
    && curl -fOL https://www.dropbox.com/s/ixt4vkbmxgab1iu/cen_patches_0.50_of.dat \
    && sleep 10 \
    && curl -fOL https://www.dropbox.com/s/2t5t1sdpshzfhpj/cen_patches_1.00_of.dat

## ==================== Install Ubuntu Base libs ===========================
## This will be our base image for OpenFace, and also the base for the compiler
## image. We only need packages which are linked

# FROM nvcr.io/nvidia/l4t-base:r32.5.0 as ubuntu_base
FROM ubuntu:18.04 as ubuntu_base

LABEL maintainer="Michael McDermott <mikemcdermott23@gmail.com>"

ARG DEBIAN_FRONTEND=noninteractive

# todo: minimize this even more
RUN apt-get update -qq \
    && apt-get install -qq curl \
    && apt-get install -qq --no-install-recommends \
    ninja-build \
    libgtk2.0-dev pkg-config \
    libopenblas-dev liblapack-dev \
    libavcodec-dev libavformat-dev libswscale-dev \
    libtbb2 libtbb-dev libjpeg-dev \
    libpng-dev libtiff-dev \
    && rm -rf /var/lib/apt/lists/*

## ==================== Build-time dependency libs ======================
## This will build and install opencv and dlib into an additional dummy
## directory, /root/diff, so we can later copy in these artifacts,
## minimizing docker layer size
## Protip: ninja is faster than `make -j` and less likely to lock up system
FROM ubuntu_base as cv_deps

WORKDIR /root/build-dep
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -qq -y \
    cmake \
    pkg-config \
    build-essential \
    checkinstall \
    g++-8 \
    && rm -rf /var/lib/apt/lists/*
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 800 --slave /usr/bin/g++ g++ /usr/bin/g++-8
RUN mkdir -p /root/diff

##        llvm clang-3.7 libc++-dev libc++abi-dev  \
## ==================== Building dlib ===========================

RUN mkdir -p dlib \
    && curl -fsSL http://dlib.net/files/dlib-19.13.tar.bz2 \
    | tar xj --strip-components 1 -C dlib \
    && mkdir -p dlib/build \
    && cd dlib/build \
    && cmake \
    -G Ninja \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu \
    .. \
    && ninja install \
    && DESTDIR=/root/diff ninja install \
    && ldconfig

## ==================== Building OpenCV ======================
ENV OPENCV_VERSION=4.1.0

RUN mkdir -p opencv \
    && curl -fsSL https://github.com/opencv/opencv/archive/${OPENCV_VERSION}.tar.gz \
    | tar xz --strip-components 1 -C opencv \
    && mkdir -p opencv_contrib \
    && curl -fsSL https://github.com/opencv/opencv_contrib/archive/4.5.2.tar.gz \
    | tar xz --strip-components 1 -C opencv_contrib \
    && mkdir -p opencv/build \
    && cd opencv/build \
    && cmake \
    -G Ninja \
    # -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D WITH_TBB=ON -D WITH_CUDA=ON \
    -D WITH_QT=OFF -D WITH_GTK=ON \
    .. \
    && ninja install \
    && DESTDIR=/root/diff ninja install

## ==================== Building OpenFace ===========================
FROM cv_deps as openface
WORKDIR /root/openface

ENV OpenFace_VERSION="OpenFace_2.2.0"
RUN curl -fsSL https://github.com/TadasBaltrusaitis/OpenFace/archive/$OpenFace_VERSION.tar.gz \
    | tar xz --strip-components 1

COPY --from=model_data /data/patch_experts/* \
    /root/openface/lib/local/LandmarkDetector/model/patch_experts/

RUN mkdir -p build && cd build \
    && cmake -G Ninja .. \
    && ninja install \
    && DESTDIR=/root/diff ninja install


## ==================== Streamline container ===========================
## Clean up - start fresh and only copy in necessary stuff
## This shrinks the image from ~8 GB to ~1.6 GB
FROM ubuntu_base as final

WORKDIR /root

# Copy in only necessary libraries
COPY --from=openface /root/diff /

# Since we "imported" the build artifacts, we need to reconfigure ld
RUN ldconfig
