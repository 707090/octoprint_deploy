
# TODO(3): Investigate hostname vs localhost for whole project
# TODO(1): Support multiple HAProxy versions
# TODO(3): Is there some way to live reload config changes?

haproxy_printer_rule_exists() {
    expect_environment_variables_set INSTANCE
    [ -f /etc/tentacles/${INSTANCE}_haproxy.cfg ]
}

haproxy_camera_rule_exists() {
    expect_environment_variables_set CAMERA_NAME
    [ -f /etc/tentacles/${CAMERA_NAME}_haproxy.cfg ]
}

reload_haproxy() {
    systemctl reload haproxy
}

add_haproxy_printer_rule() {
    echo "localhost/${INSTANCE}   ${INSTANCE}" >>/etc/tentacles/haproxy.map

    sudo -u octavia env INSTANCE=${INSTANCE} PORT=${PORT} \
        envsubst <${SCRIPT_DIR}/templates/printer_haproxy.cfg >/etc/tentacles/${INSTANCE}_haproxy.cfg

    reload_haproxy
}

remove_haproxy_printer_rule() {
    # remove backend
    rm /etc/tentacles/${INSTANCE}_haproxy.cfg
    # remove frontend url mapping
    sed "/[[:space:]]${INSTANCE}[[:space:]]*$/d" /etc/tentacles/haproxy.map

    reload_haproxy
}

add_haproxy_camera_rule() {
    sudo -u octavia env CAMERA_NAME=${CAMERA_NAME} PORT=${PORT} \
        envsubst <${SCRIPT_DIR}/templates/camera_haproxy.cfg >/etc/tentacles/${CAMERA_NAME}_haproxy.cfg
    echo "localhost/${CAMERA_NAME}   ${CAMERA_NAME}" >>/etc/tentacles/haproxy.map

    reload_haproxy

    # Update the config for this instance to point to the haproxy urls (since the proxy rules are now present)
    update_config_with_camera_urls
}

remove_haproxy_camera_rule() {
    # remove backend
    rm /etc/tentacles/${CAMERA_NAME}_haproxy.cfg
    # remove frontend url mapping
    sed "/[[:space:]]${CAMERA_NAME}[[:space:]]*$/d" /etc/tentacles/haproxy.map

    reload_haproxy

    # Update the config for this instance to point to the non-haproxy urls (since the proxy rules are now removed)
    update_config_with_camera_urls
}