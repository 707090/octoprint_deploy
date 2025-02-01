
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
    systemctl restart haproxy
}

add_haproxy_printer_rule() {
    expect_environment_variables_set INSTANCE
    source_instance_env
    echo "/${INSTANCE}/   ${INSTANCE}" >>/etc/tentacles/haproxy.map

    env INSTANCE=${INSTANCE} PORT=${PORT} \
        envsubst <${SCRIPT_DIR}/templates/printer_haproxy.cfg | sudo -u octavia tee /etc/tentacles/${INSTANCE}_haproxy.cfg >/dev/null

    reload_haproxy
}

remove_haproxy_printer_rule() {
    # remove backend
    rm /etc/tentacles/${INSTANCE}_haproxy.cfg
    # remove frontend url mapping
    sed "/[[:space:]]${INSTANCE}[[:space:]]*$/d" /etc/tentacles/haproxy.map > /etc/tentacles/haproxy.map.tmp
    mv /etc/tentacles/haproxy.map.tmp /etc/tentacles/haproxy.map

    reload_haproxy
}

add_haproxy_camera_rule() {
    expect_environment_variables_set
    source_camera_env
    env CAMERA_NAME=${CAMERA_NAME} PORT=${PORT} \
        envsubst <${SCRIPT_DIR}/templates/camera_haproxy.cfg | sudo -u octavia tee /etc/tentacles/${CAMERA_NAME}_haproxy.cfg >/dev/null
    echo "/${CAMERA_NAME}/   ${CAMERA_NAME}" >>/etc/tentacles/haproxy.map

    reload_haproxy

    # Update the config for this instance to point to the haproxy urls (since the proxy rules are now present)
    update_config_with_camera_urls
}

remove_haproxy_camera_rule() {
    # remove backend
    rm /etc/tentacles/${CAMERA_NAME}_haproxy.cfg
    # remove frontend url mapping
    sed "/[[:space:]]${CAMERA_NAME}[[:space:]]*$/d" /etc/tentacles/haproxy.map > /etc/tentacles/haproxy.map.tmp
    mv /etc/tentacles/haproxy.map.tmp /etc/tentacles/haproxy.map

    reload_haproxy

    # Update the config for this instance to point to the non-haproxy urls (since the proxy rules are now removed)
    update_config_with_camera_urls
}