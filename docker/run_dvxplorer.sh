#!/bin/bash
# Launch the ES-PTAM DVXplorer container on Jetson.
# Passes through USB (DVXplorer cameras) and X11 display (RViz/rqt).
#
# Usage:
#   ./docker/run_dvxplorer.sh                     # interactive shell
#   ./docker/run_dvxplorer.sh roscore             # run roscore directly
#   ./docker/run_dvxplorer.sh roslaunch dvs_tracking live_tracker_dvxplorer.launch

IMAGE="esptam:dvxplorer"
CONTAINER="esptam_dvxplorer"

# Allow the container to open windows on the host display
xhost +local:docker 2>/dev/null || true

docker run -it --rm \
    --name "${CONTAINER}" \
    --network host \
    --privileged \
    --env DISPLAY="${DISPLAY}" \
    --env ROS_MASTER_URI="${ROS_MASTER_URI:-http://localhost:11311}" \
    --env ROS_IP="${ROS_IP:-127.0.0.1}" \
    --volume /dev/bus/usb:/dev/bus/usb \
    --volume /tmp/.X11-unix:/tmp/.X11-unix:rw \
    "${IMAGE}" \
    "$@"
