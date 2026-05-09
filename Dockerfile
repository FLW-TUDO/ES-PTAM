# syntax=docker/dockerfile:1
# ES-PTAM – ARM64 (Jetson) image with ROS Noetic / Ubuntu 20.04
# Works on any ARM64 host (JetPack 5.x / 6.x with Ubuntu 20.04 or 22.04)
FROM --platform=linux/arm64 ros:noetic-ros-base

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

# ── Catkin workspace setup ─────────────────────────────────────────────────
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

# Use the HTTPS-only dependency file so no SSH keys are required at build time
COPY docker/dependencies_https.yaml ${CATKIN_WS}/src/dependencies_https.yaml

# ── Clone catkin dependencies ──────────────────────────────────────────────
RUN cd ${CATKIN_WS}/src \
    && vcs-import < dependencies_https.yaml

# ── Build ──────────────────────────────────────────────────────────────────
# Builds dvs_tracking, mapper_emvs_stereo and all their catkin dependencies
# (dvxplorer_ros_driver, dvs_msgs, minkindr, glog, gflags, …).
RUN source /opt/ros/${ROS_DISTRO}/setup.bash \
    && catkin build dvs_tracking mapper_emvs_stereo \
    && catkin build --summarize

# ── Shell environment ──────────────────────────────────────────────────────
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc \
    && echo "source ${CATKIN_WS}/devel/setup.bash"  >> /root/.bashrc

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
