# syntax=docker/dockerfile:1
# ES-PTAM – ARM64 (Jetson) image with ROS Noetic / Ubuntu 20.04
# Works on any ARM64 host (JetPack 5.x / 6.x, Ubuntu 20.04 or 22.04)
#
# Use a build ARG so BuildKit lint does not complain about a constant platform.
ARG TARGETARCH=arm64
FROM ros:noetic-ros-base

LABEL description="ES-PTAM DVXplorer – Event-based Stereo Parallel Tracking and Mapping" \
      arch="linux/arm64"

ENV DEBIAN_FRONTEND=noninteractive
ENV ROS_DISTRO=noetic
ENV CATKIN_WS=/catkin_ws

# ── System & ROS dependencies ──────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        git \
        curl \
        wget \
        python3-catkin-tools \
        python3-vcstool \
        python2.7 \
        software-properties-common \
        # autoconf/libtool needed by glog_catkin (builds glog from source)
        libtool \
        automake \
        autoconf \
        # USB / device support for DVXplorer
        udev \
        libusb-1.0-0-dev \
        # ROS packages
        ros-noetic-image-geometry \
        ros-noetic-tf-conversions \
        ros-noetic-camera-info-manager \
        ros-noetic-pcl-ros \
        ros-noetic-cv-bridge \
        ros-noetic-image-transport \
        ros-noetic-eigen-conversions \
        ros-noetic-tf \
        ros-noetic-nodelet \
        ros-noetic-sophus \
        ros-noetic-rviz \
        ros-noetic-rqt \
        ros-noetic-rqt-common-plugins \
    && rm -rf /var/lib/apt/lists/*

# ── libcaer from Inivation PPA (DVXplorer USB driver) ─────────────────────
# The PPA targets Ubuntu focal (20.04) and supports arm64.
RUN add-apt-repository ppa:inivation-ppa/inivation \
    && apt-get update \
    && apt-get install -y --no-install-recommends libcaer-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Build libusb 1.0.25 from source ───────────────────────────────────────
# Ubuntu 20.04 ships libusb 1.0.23 which cannot open DVXplorer on Jetson
# (JetPack 5/6 USB controller requires fixes introduced in 1.0.25).
# The Ubuntu 22.04 binary requires GLIBC_2.34 which is not in 20.04, so we
# compile from source against the container's GLIBC 2.31.
RUN curl -fsSL https://github.com/libusb/libusb/releases/download/v1.0.25/libusb-1.0.25.tar.bz2 \
        -o /tmp/libusb.tar.bz2 \
    && tar -xjf /tmp/libusb.tar.bz2 -C /tmp \
    && cd /tmp/libusb-1.0.25 \
    && ./configure --prefix=/usr --disable-udev \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && rm -rf /tmp/libusb.tar.bz2 /tmp/libusb-1.0.25

# ── Catkin workspace ───────────────────────────────────────────────────────
WORKDIR ${CATKIN_WS}
RUN mkdir -p src

SHELL ["/bin/bash", "-c"]

RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && catkin config \
        --init \
        --mkdirs \
        --extend /opt/ros/${ROS_DISTRO} \
        --merge-devel \
        --cmake-args -DCMAKE_BUILD_TYPE=Release

# ── Copy sources ───────────────────────────────────────────────────────────
COPY . ${CATKIN_WS}/src/ES-PTAM/

# Stub vicon package: replaces KumarRobotics/vicon which ships a precompiled
# x86_64-only SDK (libboost_locale-mt.so.1.53.0) that cannot link on ARM64.
# The stub provides only the vicon/Subject.h ROS message header required by
# mapper_emvs_stereo/src/calib.cpp, without any native SDK.
#
# COPY . above also copied docker/stub_packages/vicon into the ES-PTAM tree.
# Remove it so catkin only sees one package named "vicon" (the one below).
RUN rm -rf ${CATKIN_WS}/src/ES-PTAM/docker/stub_packages

COPY docker/stub_packages/vicon ${CATKIN_WS}/src/vicon/

# Use HTTPS-only dependency file (no SSH keys needed inside Docker).
COPY docker/dependencies_https.yaml ${CATKIN_WS}/src/dependencies_https.yaml

# ── Clone catkin dependencies ──────────────────────────────────────────────
RUN cd ${CATKIN_WS}/src \
    && vcs-import < dependencies_https.yaml

# ── Build ──────────────────────────────────────────────────────────────────
# Builds dvs_tracking, mapper_emvs_stereo and all transitive catkin deps
# (dvxplorer_ros_driver, dvs_msgs, minkindr, glog, gflags, vicon stub …).
RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && catkin build dvxplorer_ros_driver dvs_tracking mapper_emvs_stereo

# ── Shell environment ──────────────────────────────────────────────────────
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc \
    && echo "source ${CATKIN_WS}/devel/setup.bash"  >> /root/.bashrc

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
