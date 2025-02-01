#!/bin/bash
source ${SCRIPT_DIR}/haproxy.sh
source ${SCRIPT_DIR}/udev.sh

instance_exists() {
    expect_environment_variables_set INSTANCE
    [ -f "/etc/tentacles/${INSTANCE}_server.env" ]
}

source_instance_env() {
    source /etc/tentacles/${INSTANCE}_server.env
}

get_instances() {
    INSTANCE_ARR=()
    shopt -s nullglob
    for instance in /etc/tentacles/*_server.env; do
        INSTANCE_ARR+=("$(basename ${instance%_server.env})")
    done
    shopt -u nullglob
}

instance_systemctl() {
    expect_environment_variables_set INSTANCE
    systemctl $1 octoprint_server@${INSTANCE}.service
}

get_instance_url() {
    expect_environment_variables_set INSTANCE PORT
    if haproxy_printer_rule_exists; then
        INSTANCE_URL=http://localhost/${INSTANCE}
    else
        INSTANCE_URL=http://localhost:${PORT}
    fi
}

import_standard_instance() {
    expect_environment_variables_set SCRIPT_DIR EXISTING_INSTANCE INSTANCE PORT

    # Create config file and fill out defaulted fields
    cp ${EXISTING_INSTANCE}/config.yaml /etc/tentacles/${INSTANCE}.yaml
    chown ocatvia:octoprinters /etc/tentacles/${INSTANCE}.yaml
    if [ -f ${EXISTING_INSTANCE}/users.yaml ]; then
        if [ -f /etc/tentacles/users.yaml ]; then
            # TODO(2): Have this condition checked for in advance, and give a good error message
            return 1
        else
            cp ${EXISTING_INSTANCE}/users.yaml /etc/tentacles/users.yaml
            chown octavia:octoprinters /etc/tentacles/users.yaml
        fi
    fi

    # TODO(2): Once there is a feature to only fill fields if they are empty, use that to fill default config

    # Write environment file
    env INSTANCE=${INSTANCE} PORT=${PORT} \
        envsubst <${SCRIPT_DIR}/templates/octoprint_tentacle.env | sudo -u octavia tee /etc/tentacles/${INSTANCE}_server.env >/dev/null

    # Create symlinks to directories which should be shared across all instances
    sudo -u octavia mkdir -p /usr/share/tentacles/${INSTANCE}
    cp -r ${EXISTING_INSTANCE}/* /usr/share/tentacles/${INSTANCE}
    chown -R octavia:octoprinters /usr/share/tentacles/${INSTANCE}
}

# Create a config and environment file for a new instance and a base folder.
create_instance_config_and_folder() {
    expect_environment_variables_set SCRIPT_DIR INSTANCE PORT

    # Create config file and fill out defaulted fields
    sudo -u octavia touch /etc/tentacles/${INSTANCE}.yaml
    #TODO(3): Model size detection is a questionable setting to be default
    update_config \
        accessControl.userfile=/etc/tentacles/users.yaml \
        appearance.name=${INSTANCE} \
        feature.modelSizeDetection=false \
        plugins.discovery.upnpUuid=$(uuidgen) \
        plugins.errortracking.unique_id=$(uuidgen) \
        plugins.tracking.enabled=true \
        plugins.tracking.unique_id=$(uuidgen) \
        server.commands.serverRestartCommand="sudo systemctl restart octoprint_server@${INSTANCE}" \
        server.commands.systemRestartCommand="sudo reboot" \
        server.firstRun=false \
        server.onlineCheck.enabled=true \
        server.pluginBlacklist.enabled=true \
        webcam.ffmpeg=/usr/bin/ffmpeg

    # Write environment file
    env INSTANCE=${INSTANCE} PORT=${PORT} \
        envsubst <${SCRIPT_DIR}/templates/octoprint_tentacle.env | sudo -u octavia tee /etc/tentacles/${INSTANCE}_server.env >/dev/null

    # Create symlinks to directories which should be shared across all instances
    sudo -u octavia mkdir -p /usr/share/tentacles/${INSTANCE}
    sudo -u octavia ln -s /usr/share/tentacles/shared/plugins /usr/share/tentacles/${INSTANCE}/plugins
    sudo -u octavia ln -s /usr/share/tentacles/shared/printerProfiles /usr/share/tentacles/${INSTANCE}/printerProfiles
    sudo -u octavia ln -s /usr/share/tentacles/shared/slicingProfiles /usr/share/tentacles/${INSTANCE}/slicingProfiles
    sudo -u octavia ln -s /usr/share/tentacles/shared/translations /usr/share/tentacles/${INSTANCE}/translations
    sudo -u octavia ln -s /usr/share/tentacles/shared/uploads /usr/share/tentacles/${INSTANCE}/uploads
    sudo -u octavia ln -s /usr/share/tentacles/shared/virtualSd /usr/share/tentacles/${INSTANCE}/virtualSd

    sudo -u octavia mkdir /usr/share/tentacles/${INSTANCE}/logs
    sudo -u octavia mkdir /usr/share/tentacles/${INSTANCE}/scripts
    sudo -u octavia mkdir /usr/share/tentacles/${INSTANCE}/timelapse
    sudo -u octavia mkdir /usr/share/tentacles/${INSTANCE}/data
    #TODO(1): What is the generated folder for?
    #TODO(1): No watched folder
}

remove_instance() {
    expect_environment_variables_set INSTANCE

    #disable service
    instance_systemctl stop
    instance_systemctl disable

    #Get all cameras associated with this instance.
    #Is this right?
    get_cameras_for_instance
    for CAMERA_NAME in "${CAMERA_ARR[@]}"; do
        remove_camera
    done

    rm /etc/tentacles/${INSTANCE}.yaml
    rm /etc/tentacles/${INSTANCE}_server.env
    #remove server files
    rm -rf /usr/share/tentacles/${INSTANCE}
    #remove udev entry
    if udev_printer_rule_exists; then
        remove_udev_rule
    fi
    #remove haproxy entry
    if haproxy_printer_rule_exists; then
        remove_haproxy_printer_rule
    fi
}

# TODO(2): Add auto backup service
back_up_instance() {
    expect_environment_variables_set INSTANCE 
    echo "Creating backup of ${INSTANCE}...."
    sudo -u octavia /opt/octoprint/bin/octoprint --basedir /usr/local/tentacles/${INSTANCE} plugins backup:backup --exclude timelapse
    sudo -u octavia mkdir /usr/local/tentacles/instance_backup 2>/dev/null
    sudo -u octavia mv /usr/local/tentacles/${INSTANCE}/data/backup/*.zip /usr/local/tentacles/instance_backup
    echo "Zipped instance backup created in /usr/local/tentacles/instance_backup"
}

restore_instance() {
    expect_environment_variables_set INSTANCE BACKUP_FILE
    echo "Restoring backup of ${INSTANCE}...."
    instance_systemctl stop
    sudo -u octavia /opt/octoprint/bin/octoprint --basedir /usr/local/tentacles/${INSTANCE} plugins backup:restore $BACKUP_FILE
    instance_systemctl start
}