
# TODO: True detection logic would have some kind of "system check" for Tentacles. This is good enough for now
# 1. octavia user
# 2. octoprint virtual environment and executable file exist
# 3. /etc/tentacles and /usr/share/tentacles exist
# 4. systemd octoprint server template in place
is_tentacles_installed() {
    id -u octavia &>/dev/null && [ -f /opt/octoprint/bin/octoprint ] && [ -d /etc/tentacles/ ] && [ -d /usr/share/tentacles/ ] && [ -f /etc/systemd/system/octoprint_server@.service ]
}

create_tentacles_user() {
    expect_environment_variables_set SCRIPT_DIR OS_FAMILY
    groupadd octoprinters
    useradd --system --no-create-home --shell /usr/sbin/nologin -g octoprinters octavia
    usermod -aG dialout,video octavia
    if [[ "$OS_FAMILY" == "arch" ]]; then
        usermod -aG uucp,video octavia
    fi

    cp ${SCRIPT_DIR}/static/999_octoprint_sudoer /etc/sudoers.d
}

remove_tentacles_user() {
    rm /etc/sudoers.d/999_octoprint_sudoer

    userdel octavia
    groupdel octoprinters
}

join_octoprinters_group() {
    usermod -aG octoprinters $SUDO_USER
}

_make_permissioned_directory() {
    mkdir --mode 774 --parents $1
    chown -R octavia:octoprinters $1
}

is_octoprint_installed() {
    [ -f "/opt/octoprint/bin/octoprint" ]
}

# TODO(1): Support bringing in an existing download of octoprint (particularly useful to speed up installs on OctoPi)
install_octoprint() {
    set -e

    _make_permissioned_directory /var/cache/tentacles/

    python3 -m venv /opt/octoprint
    chown -R octavia:octoprinters /opt/octoprint/
    #update pip
    sudo -u octavia /opt/octoprint/bin/pip --cache-dir=/var/cache/tentacles/pip install --upgrade pip
    #pre-install wheel
    sudo -u octavia /opt/octoprint/bin/pip --cache-dir=/var/cache/tentacles/pip install wheel
    #install octoprint
    sudo -u octavia /opt/octoprint/bin/pip --cache-dir=/var/cache/tentacles/pip install OctoPrint
    #install yq for config updates
    sudo -u octavia /opt/octoprint/bin/pip --cache-dir=/var/cache/tentacles/pip install yq
    set +e
}

uninstall_octoprint() {
    rm -r /var/cache/tentacles/
    rm -r /opt/octoprint
}

install_tentacles() {
    set -e
    create_tentacles_user
    install_octoprint

    _make_permissioned_directory /etc/tentacles/
    _make_permissioned_directory /usr/share/tentacles/

    sudo -u octavia mkdir /usr/share/tentacles/shared
    sudo -u octavia mkdir /usr/share/tentacles/shared/plugins
    sudo -u octavia mkdir /usr/share/tentacles/shared/printerProfiles
    sudo -u octavia mkdir /usr/share/tentacles/shared/slicingProfiles
    sudo -u octavia mkdir /usr/share/tentacles/shared/translations
    sudo -u octavia mkdir /usr/share/tentacles/shared/uploads
    sudo -u octavia mkdir /usr/share/tentacles/shared/virtualSd

    sudo -u octavia touch /etc/tentacles/users.yaml
    # TODO(0): Use the octoprint_deploy admin-setting script
    prompt_confirm "Copy over the user file"

    cp ${SCRIPT_DIR}/static/octoprint_server@.service /etc/systemd/system/
    systemctl daemon-reload
    set +e
}

uninstall_tentacles() {
    # Remove all instances. This is currently somewhat redundant since all instance config lives in /etc/tentacles removed below, but this is future-proofing in case we add logic later.
    get_instances
    for INSTANCE in ${INSTANCE_ARR[@]}; do
        remove_instance
    done

    if is_haproxy_installed; then
        uninstall_haproxy
    fi
    if is_ustreamer_installed; then
        uninstall_ustreamer
    fi
    if is_mjpg_streamer_installed; then
        uninstall_mjpg_streamer
    fi
    if is_camera_streamer_installed; then
        uninstall_camera_streamer
    fi


    rm /etc/systemd/system/octoprint_server@.service
    systemctl daemon-reload

    rm -r /etc/tentacles/
    rm -r /usr/share/tentacles/

    rm /etc/udev/rules.d/99-octoprint.rules 

    uninstall_octoprint
    remove_tentacles_user
}

is_haproxy_installed() {
    [ -n $(which haproxy) ] && [ -d /etc/haproxy/haproxy.cfg.d ] && [ -f /etc/systemd/system/haproxy.service.d/haproxy_systemd_octoprint_override.conf ]
}

# TODO(3): make HAProxy run separate in systemd so its dedicated
# TODO(1): This isnt actaully installing HAProxy, its already installed, this is just doing setup
install_haproxy() {
    set -e
    
    expect_environment_variables_set SCRIPT_DIR

    mkdir -p /etc/haproxy/haproxy.cfg.d
    ln -sf /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.d/haproxy_original.cfg

    cp ${SCRIPT_DIR}/static/haproxy_frontend.cfg /etc/tentacles/
    chown octavia:octoprinters /etc/tentacles/haproxy_frontend.cfg
    sudo -u octavia touch /etc/tentacles/haproxy.map 
    

    mkdir -p /etc/systemd/system/haproxy.service.d/
    cp ${SCRIPT_DIR}/static/haproxy_systemd_octoprint_override.conf /etc/systemd/system/haproxy.service.d/
    systemctl daemon-reload

    systemctl enable haproxy
    systemctl restart haproxy
    
    set +e
}

uninstall_haproxy() {
    get_instances
    for INSTANCE in ${INSTANCE_ARR[@]}; do
        if haproxy_printer_rule_exists; then 
            remove_haproxy_printer_rule
        fi
        get_cameras_for_instance
        for CAMERA_NAME in ${CAMERA_ARR[@]}; do
            remove_haproxy_camera_rule
        done
    done

    rm -r /etc/haproxy/haproxy.cfg.d

    rm /etc/tentacles/haproxy_frontend.cfg
    rm /etc/tentacles/haproxy.map 

    rm /etc/systemd/system/haproxy.service.d/haproxy_systemd_octoprint_override.conf
    systemctl daemon-reload

    systemctl stop haproxy
    systemctl disable haproxy
}

get_installed_streamers() {
    INSTALLED_STREAMERS=()
    if is_ustreamer_installed; then
        INSTALLED_STREAMERS+=("uStreamer")
    fi
    if is_mjpg_streamer_installed; then
        INSTALLED_STREAMERS+=("mjpg-streamer")
    fi
    if is_camera_streamer_installed; then
        INSTALLED_STREAMERS+=("camera-streamer")
    fi
}

remove_all_cameras_using_streamer() {
    expect_environment_variables_set 1
    STREAMER_TO_REMOVE=$1

    get_instances
    for INSTANCE in ${INSTANCE_ARR[@]}; do
        get_cameras_for_instance
        for CAMERA_NAME in ${CAMERA_ARR[@]}; do
            source_camera_env
            if [ "${STREAMER}" = "${STREAMER_TO_REMOVE}" ]; then
                remove_camera
            fi
        done
    done
}

is_ustreamer_installed() {
    [ -f "/opt/ustreamer/ustreamer" ]
}

install_ustreamer() {
    set -e
    expect_environment_variables_set SCRIPT_DIR
    #TODO: add these commands to the log
    # Remove existing install if present
    if [ -d /opt/ustreamer ]; then
        rm -r /opt/ustreamer
    fi
    git -C /opt/ clone --depth=1 https://github.com/pikvm/ustreamer
    make -C /opt/ustreamer > /dev/null
    
    if [ -f "/opt/ustreamer/ustreamer.bin" ]; then
        ln -s /opt/ustreamer/ustreamer.bin /opt/ustreamer/ustreamer
    fi

    chown -R octavia:octoprinters /opt/ustreamer/

    cp ${SCRIPT_DIR}/static/octoprint_camera_ustreamer@.service /etc/systemd/system
    systemctl daemon-reload
    set +e
}

uninstall_ustreamer() {
    remove_all_cameras_using_streamer "uStreamer"

    rm /etc/systemd/system/octoprint_camera_ustreamer@.service
    systemctl daemon-reload

    rm -rf /opt/ustreamer 2>/dev/null
}

is_mjpg_streamer_installed() {
    [ -f "/opt/mjpg_streamer/mjpg_streamer" ]
}

install_mjpg_streamer() {
    set -e
    expect_environment_variables_set SCRIPT_DIR
    # Remove existing install if present
    if [ -d /opt/mjpg_streamer ]; then
        rm -r /opt/mjpg_streamer
    fi
    git -C /opt/ clone https://github.com/jacksonliam/mjpg-streamer.git mjpeg
    make -C /opt/mjpeg/mjpg-streamer-experimental > /dev/null
    
    #TODO(3): Is pulling the experimental version still correct?
    mv /opt/mjpeg/mjpg-streamer-experimental /opt/mjpg_streamer
    rm -rf /opt/mjpeg

    chown -R octavia:octoprinters /opt/mjpg_streamer/
    
    cp ${SCRIPT_DIR}/static/octoprint_camera_mjpg_streamer@.service /etc/systemd/system
    systemctl daemon-reload
    set +e
}

uninstall_mjpg_streamer() {
    remove_all_cameras_using_streamer "mjpg-streamer"
    
    rm /etc/systemd/system/octoprint_camera_mjpg_streamer@.service
    systemctl daemon-reload

    rm -rf /opt/mjpg_streamer 2>/dev/null
}

is_camera_streamer_installed() {
    [ -f "/opt/camera-streamer/camera-streamer" ]
}

install_camera_streamer() {
    set -e
    expect_environment_variables_set SCRIPT_DIR
    # Remove existing install if present
    if [ -d /opt/camera-streamer ]; then
        rm -r /opt/camera-streamer
    fi
    #install camera-streamer
    git -C /opt/ clone https://github.com/ayufan-research/camera-streamer.git --recursive
    make -C /opt/camera-streamer > /dev/null

    chown -R octavia:octoprinters /opt/camera-streamer/

    cp ${SCRIPT_DIR}/static/octoprint_camera_camera_streamer@.service /etc/systemd/system
    cp ${SCRIPT_DIR}/static/octoprint_camera_pi_camera_streamer@.service /etc/systemd/system
    systemctl daemon-reload

    set +e
}

uninstall_camera_streamer() {
    remove_all_cameras_using_streamer "camera-streamer"

    rm /etc/systemd/system/octoprint_camera_camera_streamer@.service
    rm /etc/systemd/system/octoprint_camera_pi_camera_streamer@.service
    systemctl daemon-reload

    rm -rf /opt/camera_streamer 2>/dev/null
}
