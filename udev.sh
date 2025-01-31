printer_udev_name() {
    expect_environment_variables_set INSTANCE
    echo "octo_${INSTANCE}_printer"
}

camera_udev_name() {
    expect_environment_variables_set CAMERA_NAME
    echo "octo_${CAMERA_NAME}"
}

check_udev_setup() {
    [ ! -f /etc/udev/rules.d/99-octoprint.rules ]
}

setup_tentacles_udev() {
    expect_environment_variables_set SCRIPT_DIR
    cp ${SCRIPT_DIR}/static/99-octoprint.rules /etc/udev/rules.d/

    reload_udev
}

verify_no_duplicate_printer_serial_numbers() {
    expect_environment_variables_set SERIAL_NUMBER
    shopt -s nullglob
    for udev_rule in /etc/tentacles/*_printer_udev.rules; do
        if grep -q "ATTRS{serial}==\"${SERIAL_NUMBER}\"" $udev_rule; then 
            CONFLICTING_UDEV_FILE=$udev_rule
            shopt -u nullglob
            return 1
        fi
    done
    shopt -u nullglob
    return 0
}

verify_no_duplicate_camera_serial_numbers() {
    expect_environment_variables_set SERIAL_NUMBER
    shopt -s nullglob
    for udev_rule in /etc/tentacles/*_camera_*_udev.rules; do
        if grep -q "ATTRS{serial}==\"${SERIAL_NUMBER}\"" $udev_rule; then 
            CONFLICTING_UDEV_FILE=$udev_rule
            shopt -u nullglob
            return 1
        fi
    done
    shopt -u nullglob
    return 0
}

reload_udev() {
    udevadm control --reload-rules
    udevadm trigger
}

udev_printer_rule_exists() {
    expect_environment_variables_set INSTANCE
    [ -f /etc/tentacles/${INSTANCE}_printer_udev.rules ]
}

add_serial_number_printer_udev_rule() {
    expect_environment_variables_set SCRIPT_DIR INSTANCE SERIAL_NUMBER
    sudo -u octavia env SERIAL_NUMBER=$SERIAL_NUMBER UDEV_NAME=$(printer_udev_name) \
        envsubst <${SCRIPT_DIR}/templates/udev_serial_number_printer_rule.rules >/etc/tentacles/${INSTANCE}_printer_udev.rules

    # Update config for the instance
    # TODO: removing all other additional ports and resetting the array might be questionable
    update_config \
        serial.port=/dev/$(printer_udev_name) \
        serial.additionalPorts=["/dev/$(printer_udev_name)"]

    reload_udev
}

add_usb_printer_udev_rule() {
    echo "Adding printer with ${SCRIPT_DIR} $INSTANC2E $USB_ADDRESS"
    expect_environment_variables_set SCRIPT_DIR INSTANCE USB_ADDRESS
    sudo -u octavia env USB_ADDRESS=$USB_ADDRESS UDEV_NAME=$(printer_udev_name) \
        envsubst <${SCRIPT_DIR}/templates/udev_usb_printer_rule.rules >/etc/tentacles/${INSTANCE}_printer_udev.rules

    # Update config for the instance
    update_config \
        serial.port=/dev/$(printer_udev_name) \
        serial.additionalPorts=["/dev/$(printer_udev_name)"]
    
    reload_udev
}

remove_printer_udev_rule() {
    expect_environment_variables_set INSTANCE
    rm /etc/tentacles/${INSTANCE}_printer_udev.rules
}

udev_camera_rule_exists() {
    expect_environment_variables_set CAMERA_NAME
    [ -f /etc/tentacles/${CAMERA_NAME}_udev.rules ]
}

add_serial_number_camera_udev_rule() {
    expect_environment_variables_set SCRIPT_DIR CAMERA_NAME SERIAL_NUMBER
    sudo -u octavia env SERIAL_NUMBER=$SERIAL_NUMBER UDEV_NAME=$(camera_udev_name) \
        envsubst <${SCRIPT_DIR}/templates/udev_serial_number_camera_rule.rules >/etc/tentacles/${CAMERA_NAME}_udev.rules

    reload_udev
}

add_usb_camera_udev_rule() {
    expect_environment_variables_set SCRIPT_DIR CAMERA_NAME USBCAM
    sudo -u octavia env USB_ADDRESS=$USBCAM UDEV_NAME=$(camera_udev_name) \
        envsubst <${SCRIPT_DIR}/templates/udev_serial_number_camera_rule.rules >/etc/tentacles/${CAMERA_NAME}_udev.rules

    reload_udev
}

remove_camera_udev_rule() {
    expect_environment_variables_set CAMERA_NAME
    rm /etc/tentacles/${CAMERA_NAME}_udev.rules
}

detect_printer() {
    #reset detection info
    SERIAL_NUMBER=''
    USB_ADDRESS_TENTATIVE=''
    USB_ADDRESS=''

    dmesg -C
    echo
    echo
    echo "Plug your printer in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$SERIAL_NUMBER" ]] && [[ $counter -lt 60 ]]; do
        USB_ADDRESS_TENTATIVE=$(dmesg | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\|cp210x\|ch34x\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\|cp210x\|ch34x\).*/\2/p')
        SERIAL_NUMBER=$(dmesg | sed -n -e 's/^.*SerialNumber: //p')
        counter=$(($counter + 1))
        if [[ -n "$USB_ADDRESS_TENTATIVE" ]] && [[ -z "$SERIAL_NUMBER" ]]; then
            break
        fi
        sleep 1
    done
    dmesg -C

    #No serial number
    if [ -z "$SERIAL_NUMBER" ] && [ -n "$USB_ADDRESS_TENTATIVE" ]; then
        echo "Printer Serial Number not detected."
        echo "The physical USB port will be used."
        echo "USB hubs and printers detected this way must stay plugged into the same USB positions on your machine."
        echo
        USB_ADDRESS=$USB_ADDRESS_TENTATIVE
        echo "Your printer will be setup at the following usb address: ${cyan}$USB${white}"
        echo
    else
        echo -e "Serial number detected as: ${cyan}$SERIAL_NUMBER${white}"
        if ! verify_no_duplicate_printer_serial_numbers; then
            echo "Duplicate printer serial number found in udev rule $CONFLICTING_UDEV_FILE. Creating device file aliases for both printers would cause conflicting rules in udev."
            return 1;
        fi 
        echo
    fi
    #Failed state. Nothing detected
    if [ -z "$SERIAL_NUMBER" ] && [ -z "$USB_ADDRESS_TENTATIVE" ]; then
        if [ "$firstrun" == "false" ]; then

            echo
            echo "${red}No printer was detected during the detection period.${white}"
            echo "Check your USB cable (power only?) and try again."
            echo
            echo
            main_menu
        else
            echo "You can add a udev rule later from the Utilities menu."
        fi
    fi
}

#TODO(3): refactor detect_printer with dmesg --follow
# detect_printer() {
#     #reset detection info
#     SERIAL_NUMBER=''
#     USB_ADDRESS_TENTATIVE=''
#     USB_ADDRESS=''

#     # Run dmesg with a timeout and search for the pattern
#     timeout 10 dmesg --since "now" --follow | grep --line-buffered -m 1 "cdc_acm\|ftdi_sio\|ch341\|cp210x\|ch34x"
#     # If the timeout occurs and no pattern is found
#     if [[ $? -eq 124 ]]; then
#         echo "No printer detected."
#     fi
# }

detect_camera() {
    echo
    echo
    echo "Verify the camera is currently unplugged from USB....."
    if prompt_confirm "Is the camera you are trying to detect unplugged from USB?"; then
        readarray -t c1 < <(ls -1 /dev/v4l/by-id/*index0 2>/dev/null)
    fi
    dmesg -C
    echo "Plug your camera in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$SERIAL_NUMBER" ]] && [[ $counter -lt 60 ]]; do
        SERIAL_NUMBER=$(dmesg | sed -n -e 's/^.*SerialNumber: //p')
        TEMPUSBCAM=$(dmesg | sed -n -e 's|^.*input:.*/\(.*\)/input/input.*|\1|p')
        counter=$(($counter + 1))
        if [[ -n "$TEMPUSBCAM" ]] && [[ -z "$SERIAL_NUMBER" ]]; then
            break
        fi
        sleep 1
    done
    readarray -t c2 < <(ls -1 /dev/v4l/by-id/*index0 2>/dev/null)
    #https://stackoverflow.com/questions/2312762
    #TODO: what if there is more than one element?
    BYIDCAM=($(echo ${c2[@]} ${c1[@]} | tr ' ' '\n' | sort | uniq -u))
    echo $BYIDCAM
    dmesg -C
}