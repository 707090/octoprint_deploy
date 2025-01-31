#!/bin/bash

instance_and_id_to_camera_name() {
    expect_environment_variables_set INSTANCE CAMERA_ID
    CAMERA_NAME="${INSTANCE}_camera_${CAMERA_ID}"
}

camera_name_to_instance_and_id() {
    expect_environment_variables_set CAMERA_NAME
    INSTANCE=$(awk -F'_camera_' '{print $1}' <<< "${CAMERA_NAME}")
    CAMERA_ID=$(awk -F'_camera_' '{print $2}' <<< "${CAMERA_NAME}")
}

camera_exists() {
    expect_environment_variables_set CAMERA_NAME
    [ -f /etc/tentacles/${CAMERA_NAME}.env ]
}

get_camera_stream_url() {
    expect_environment_variables_set CAMERA_NAME PORT
    if haproxy_camera_rule_exists; then
        STREAM_URL="http://localhost/${CAMERA_NAME}/?action=stream"
    else
        STREAM_URL="http://localhost:${PORT}/?action=stream"
    fi
}

get_camera_snapshot_url() {
    expect_environment_variables_set CAMERA_NAME PORT
    if haproxy_camera_rule_exists; then
        SNAPSHOT_URL="http://localhost/${CAMERA_NAME}/?action=snapshot"
    else
        SNAPSHOT_URL="http://localhost:${PORT}/?action=snapshot"
    fi
}

get_cameras_for_instance() {
    expect_environment_variables_set INSTANCE
    CAMERA_ARR=()
    shopt -s nullglob
    for camera in /etc/tentacles/${INSTANCE}_camera*.env; do
        CAMERA_ARR+=("$(basename ${camera%.env})")
    done
    shopt -u nullglob
}

get_first_free_camera_id_for_instance() {
    expect_environment_variables_set INSTANCE
    get_cameras_for_instance
    TAKEN_CAMERA_IDS=()
    for CAMERA_NAME in "${CAMERA_ARR[@]}"; do
        camera_name_to_instance_and_id
        TAKEN_CAMERA_IDS+=("${CAMERA_ID}")
    done
    CAMERA_ID=0
    while [[ " ${TAKEN_CAMERA_IDS[@]} " =~ " ${CAMERA_ID} " ]]; do
        ((CAMERA_ID++))
    done
}

get_camera_service_name() {
    expect_environment_variables_set STREAMER CAMERA_TYPE
    case "$STREAMER" in
    "uStreamer")
        CAMERA_SERVICE_NAME=octoprint_camera_ustreamer
        ;;
    "mjpeg-streamer")
        CAMERA_SERVICE_NAME=octoprint_camera_mjpg_streamer
        ;;
    "camera-streamer")
        if [[ "${CAMERA_TYPE}" == "pi" ]]; then
            CAMERA_SERVICE_NAME=octoprint_camera_pi_camera_streamer
        else
            CAMERA_SERVICE_NAME=octoprint_camera_camera_streamer
        fi
        ;;
    *)
        # TODO: fatal_error? Maybe just a minor error
        return 1
    esac
}

camera_systemctl() {
    expect_environment_variables_set CAMERA_NAME
    get_camera_service_name
    systemctl $1 ${CAMERA_SERVICE_NAME}@${CAMERA_NAME}.service
}

source_camera_env() {
    expect_environment_variables_set CAMERA_NAME
    source /etc/tentacles/${CAMERA_NAME}.env
}

update_config_with_camera_urls() {
    expect_environment_variables_set CAMERA_NAME PORT
    # Set the instance for update_config based on camera name
    camera_name_to_instance_and_id

    # Update the config for this instance
    get_camera_stream_url
    get_camera_snapshot_url

    update_config \
        plugins.classicwebcam.snapshot=${SNAPSHOT_URL} \
        plugins.classicwebcam.stream=${STREAM_URL}
}

add_camera() {
    expect_environment_variables_set STREAMER

    if [[ "${STREAMER}" == "uStreamer" ]]; then
        _add_ustreamer_camera
    elif [[ "${STREAMER}" == "mjpg-streamer" ]]; then
        _add_mjpg_streamer_camera
    elif [[ "${STREAMER}" == "camera-streamer" ]]; then
        _add_camera_streamer_camera
    else
        # TODO(3): fatal error
        return 1
    fi

    update_config_with_camera_urls
    camera_systemctl enable
    camera_systemctl start
}

_add_ustreamer_camera() {
    expect_environment_variables_set SCRIPT_DIR CAMERA_NAME CAMERA_TYPE DEVICE RESOLUTION FRAMERATE PORT
    if ! is_ustreamer_installed; then
        return 1
    fi

    # If we are adding a PI cam, prefix the ustreamer command with libcamerafy
    LIBCAMERAFY_BINARY_OR_EMPTY=$([[ "${CAMERA_TYPE}" == "pi" ]] && echo "/usr/bin/libcamerify" || echo "")
    sudo -u octavia env DEVICE=${DEVICE} RESOLUTION=${RESOLUTION} FRAMERATE=${FRAMERATE} PORT=${PORT} LIBCAMERAFY_BINARY_OR_EMPTY=$LIBCAMERAFY_BINARY_OR_EMPTY CAMERA_TYPE=${CAMERA_TYPE} \
        envsubst <${SCRIPT_DIR}/templates/octoprint_camera_ustream.env >/etc/tentacles/${CAMERA_NAME}.env
}

_add_mjpg_streamer_camera() {
    expect_environment_variables_set SCRIPT_DIR CAMERA_NAME CAMERA_TYPE DEVICE RESOLUTION FRAMERATE PORT
    if ! is_mjpg_streamer_installed; then
        return 1
    fi

    # TODO(0): test other camera software
    sudo -u octavia env DEVICE=${DEVICE} RESOLUTION=${RESOLUTION} FRAMERATE=${FRAMERATE} PORT=${PORT} CAMERA_TYPE=${CAMERA_TYPE} \
        envsubst <${SCRIPT_DIR}/templates/octoprint_camera_mjpg_stream.env >/etc/tentacles/${CAMERA_NAME}.env
}

_add_camera_streamer_camera() {
    expect_environment_variables_set SCRIPT_DIR CAMERA_NAME CAMERA_TYPE DEVICE RESOLUTION FRAMERATE PORT
    if ! is_camera_streamer_installed; then
        return 1
    fi
    #convert RES into WIDTH and HEIGHT for camera-streamer
    CAMWIDTH=$(sed -r 's/^([0-9]+)x[0-9]+/\1/' <<<"${RESOLUTION}")
    CAMHEIGHT=$(sed -r 's/^[0-9]+x([0-9]+)/\1/' <<<"${RESOLUTION}")
    
    sudo -u octavia env DEVICE=${DEVICE} WIDTH=${CAMWIDTH} HEIGHT=${CAMHEIGHT} FRAMERATE=${FRAMERATE} PORT=${PORT} CAMERA_TYPE=${CAMERA_TYPE} \
        envsubst <${SCRIPT_DIR}/templates/octoprint_camera_camera_stream.env >/etc/tentacles/${CAMERA_NAME}.env
}

remove_camera() {
    expect_environment_variables_set CAMERA_NAME
    if [ -f /etc/tentacles/${CAMERA_NAME}.env ]; then
        source_camera_env

        # TODO(2): This is kind of a hack to satisfy camera_systemctl, since I am only bothering to set CAMERA_TYPE in the camera-streamer envs since its the only one that it makes a difference. This will break if I add IP cameras.
        if [ -z "CAMERA_TYPE" ]; then
            CAMERA_TYPE="usb"
        fi

        if [ -z "$STREAMER" ]; then
            # TODO(2): add fatal_error function which make a big warning screen and closes the program
            echo "No streamer field set in camera environment file. Cannot remove camera"
            return 1
        elif [ "$STREAMER" = "uStreamer" ] || [ "$STREAMER" = "mjpg-streamer" ] || [ "$STREAMER" = "camera-streamer" ]; then
            camera_systemctl stop
            camera_systemctl disable
        else
            echo "Found camera with correct instance and camera index but an unknown streamer type: $STREAMER. Will not be able to shut down systemd service, but removing anyway."
        fi

        rm /etc/tentacles/${CAMERA_NAME}.env
        
        if udev_camera_rule_exists; then
            remove_camera_udev_rule
        fi
        if haproxy_camera_rule_exists; then
            remove_haproxy_camera_rule
        fi
    else
        camera_name_to_instance_and_id
        echo "Could not locate camera for instance \"${INSTANCE}\" with ID ${CAMERA_ID}."
    fi
}
