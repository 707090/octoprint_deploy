#!/bin/bash
white=$(echo -en "\e[39m")
green=$(echo -en "\e[92m")
red=$(echo -en "\e[91m")
magenta=$(echo -en "\e[35m")
cyan=$(echo -en "\e[96m")
yellow=$(echo -en "\e[93m")

# Expects the instance array to be populated with the instances to select from
user_select_instance() {
    PS3="$1"
    CHOICES=${INSTANCE_ARR}
    if [[ "$2" == true ]]; then
        #TODO(0): Why are there multiple quits showing up?
        CHOICES+=("Quit")
    fi
    select opt in "${CHOICES[@]}"; do
        SELECTED=$opt
        if [ "${SELECTED}" == Quit ]; then
            #TODO(3): Improve the menu system so that it does not always have to go all the way to main menu
            main_menu
        fi
        break
    done
}

# Expects the camera array to be populated with the cameras to select from
user_select_camera() {
    PS3="$1"
    CHOICES=$CAMERA_ARR
    if [[ "$2" == true ]]; then
        CHOICES+=("Quit")
    fi
    select opt in "${CHOICES[@]}"; do
        SELECTED=$opt
        if [ "${SELECTED}" == Quit ]; then
            main_menu
        fi
        break
    done
}

user_input_instance_name() {
    while true; do
        echo "${green}Enter the name for new printer/instance (no spaces):${white}"
        read INSTANCE
        if [ -z "${INSTANCE}" ]; then
            echo "Please provide an instance name"
            continue
        fi

        if has_space "${INSTANCE}"; then
            echo "Instance names must not have spaces"
            continue
        fi

        if instance_exists; then
            echo "Already have instance for ${INSTANCE}."
            main_menu
        fi
        break
    done
}

print_octavia_header() {
    echo "_.--.__.-'\"\"\`-.__.--.__.-'\"\"\`-.__.--.__.-'\"\"\`-.__.--.__.-'\"\"\`"
    echo "--'\"\"\`-.__.-'\"\"\`--'\"\"\`-.__.-'\"\"\`--'\"\"\`-.__.-'\"\"\`--'\"\"\`-.__.-'"
    echo "                             ___" 
    echo "    .-.-.   .-.-.   .-.-.   /ö ö\   .-.-.   .-.-.   .-.-.   " 
    echo " \ / / \ \ / / \ \ / / \ \  \___/  / / \ \ / / \ \ / / \ \ / " 
    echo "\`-\`-'   \`-\`-'   \`-\`-'   \`-\`-'   \`-\`-'   \`-\`-'   \`-\`-'   \`-\`-'"
    echo "------------------------- [Octavia] -------------------------"
}

print_tentacles_menu_header() {
    print_octavia_header
    if ! is_tentacles_installed; then
        printf "%-35s: %s\n" "Tentacles Version" "Not installed."
    else
        printf "%-35s: %s\n" "Tentacles Version" $TENTACLES_VERSION
        printf "%-35s: %s\n" "Octoprint user:group" "octavia:octoprinters"
        printf "%-35s: %s\n" "Config directory" /etc/tentacles
        printf "%-35s: %s\n" "Instance directories" /usr/share/tentacles
        get_instances
        if [[ ${#INSTANCE_ARR[@]} -eq 0 ]]; then
            printf "%-35s: %s\n" "Instances" None
        else
            echo "Instances"
            for INSTANCE in ${INSTANCE_ARR[@]}; do
                SYSTEMD_STATUS=$(instance_systemctl is-active)
                color_systemd_status
                printf "%-35s: %s\n" "- ${INSTANCE}" ${SYSTEMD_STATUS}
            done 
        fi

    fi
    echo "-------------------------------------------------------------"
    echo
    echo
}

print_instance_menu_header() {
    expect_environment_variables_set INSTANCE
    print_octavia_header
    if ! instance_exists; then
        # Should not be possible to get here
        printf "%-35s: %s\n" "Instance ${INSTANCE}" "Does not exist"
    else
        source_instance_env # sets CONFIG_FILE and BASE_DIR
        SYSTEMD_STATUS=$(instance_systemctl is-active)
        color_systemd_status
        get_instance_url # sets INSTANCE_URL

        printf "%-35s: %s\n" "Instance" ${INSTANCE}
        
        # TODO(3): eli5 mode which verbose explanations of what everything means
        printf "%-35s: %s\n" "SystemD status" ${SYSTEMD_STATUS}
        printf "%-35s: %s\n" "Config file" ${CONFIG_FILE}
        printf "%-35s: %s\n" "Instance directory" ${BASE_DIR}
        if udev_printer_rule_exists; then
            printf "%-35s: %s\n" "Device alias file" /dev/$(printer_udev_name)
        else
            printf "%-35s: %s\n" "Device alias file" "No device alias"
        fi
        printf "%-35s: %s\n" "Url" ${INSTANCE_URL}

        get_cameras_for_instance
        if [ ${#CAMERA_ARR[@]} -eq 0 ]; then
            printf "%-35s: %s\n" "Cameras" None
        else
            echo "Cameras"
            for CAMERA_NAME in ${CAMERA_ARR[@]}; do
                source_camera_env
                SYSTEMD_STATUS=$(camera_systemctl is-active)
                color_systemd_status
                printf "%-35s: %s\n" "- ${CAMERA_NAME}" ${SYSTEMD_STATUS}
            done 
        fi
    fi
    echo "-------------------------------------------------------------"
    echo
    echo
}

# TODO: add camera menu header (type, config,)
print_camera_menu_header() {
    expect_environment_variables_set CAMERA_NAME
    print_octavia_header
    if ! camera_exists; then
        # Should not be possible to get here
        printf "%-35s: %s\n" "Camera ${CAMERA_NAME}" "Does not exist"
    else
        source_camera_env # sets STREAMER and CAMERA_TYPE
        SYSTEMD_STATUS=$(camera_systemctl is-active)
        color_systemd_status
        get_camera_stream_url # sets STREAM_URL

        printf "%-35s: %s\n" "Camera" ${CAMERA_NAME}
        printf "%-35s: %s\n" "SystemD status" ${SYSTEMD_STATUS}
        printf "%-35s: %s\n" "Camera type" ${CAMERA_TYPE}
        printf "%-35s: %s\n" "Video streamer" ${STREAMER}
        if udev_camera_rule_exists; then
            printf "%-35s: %s\n" "Device alias file" /dev/$(camera_udev_name)
        else
            printf "%-35s: %s\n" "Device alias file" "No device alias"
        fi
        printf "%-35s: %s\n" "Stream Url" ${STREAM_URL}
    fi
    echo "-------------------------------------------------------------"
    echo
    echo
}

# Define an array of recognized OSes with their required versions
# Format: "os_id:required_version"
RECOGNIZED_OSES=("raspbian:0" "debian:0" "ubuntu:0" "linuxmint:0" "centos:0" "fedora:0" "arch:0" "opensuse-leap:0" "opensuse-tumbleweed:0")

os_family() {
    case $1 in
    "raspbian"|"ubuntu"|"debian"|"linuxmint")
        OS_FAMILY="debian"
        break
        ;;
    "fedora"|"centos")
        OS_FAMILY="rhel"
        break
        ;;
    "arch")
        OS_FAMILY="arch"
        break
        ;;
    "opensuse-leap"|"opensuse-tumbleweed")
        OS_FAMILY="suse"
        break
        ;;
    *)  
        echo "Unexpected value for OS family. This function should only be called with one of the known OS values."
        exit 1
        ;;
    esac
}

# TODO: Verify this menu works on other OSes
detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
    elif [ -f /usr/lib/os-release ]; then
        source /usr/lib/os-release
    fi


    # Check if ID and VERSION_ID match any in the RECOGNIZED_OSES array
    for recognized_os_and_version in "${RECOGNIZED_OSES[@]}"; do
        # Split the pair into ID and required version
        IFS=":" read -r recoginized_os_id minimum_version <<< "$recognized_os_and_version"

        # Check if ID matches and VERSION_ID is greater than or equal to the required version
        if [[ "$ID" == "$recoginized_os_id" ]]; then
            # Check that the version we have is greater than or equal to the minimum version
            if [ "$(echo -e "$VERSION_ID\n$minimum_version" | sort --version-sort | tail -n1)" == "$VERSION_ID" ]; then
                echo "$ID version $VERSION_ID is a recognized operating system. Proceeding"
                os_family $ID
                return;
            else
                echo "$ID version $VERSION_ID is lower than the required version $minimum_version. There are no garuntees that it will install correctly."
                if prompt_confirm "Would you like to proceed anyway? "; then
                    os_family $like_id
                    return;
                else
                    echo "Tentacles installation failed."
                    exit 1
                fi
            fi
        fi
    done

    for like_id in $ID_LIKE; do
        for recognized_os_and_version in "${RECOGNIZED_OSES[@]}"; do
            # Split the pair into OS_ID and required version
            IFS=":" read -r recoginized_os_id minimum_version <<< "$recognized_os_and_version"

            # Check if like_id matches and VERSION_ID is greater than or equal to the required version
            if [[ "$like_id" == "$recoginized_os_id" ]]; then
                echo "$ID is not a recognized operating system, but is like $like_id. Unable to verify that Tentacles will install properly, but the install will attempt to treat it like $like_id."
                if prompt_confirm "Would you like to proceed? "; then
                    os_family $like_id
                    return;
                else
                    echo "Tentacles installation failed."
                    exit 1
                fi
            fi
        done
    done

    echo "Unrecognized operating system $ID. Tentacles is known to work with the following operating systems and versions: "
    echo "[ ${RECOGNIZED_OSES[@]} ]"
    echo "$ID is also not listed like any of the recognized systems in /etc/os-releases. If you know it is similar enough to one of the listed operating systems an install can be attempted where it is treated like that system."
    if prompt_confirm "Would you like to attempt an install? "; then
        select opt in "${RECOGNIZED_OSES[@]}"; do
            os_family $opt
            return;
        done
    else
        echo "Tentacles installation failed."
        exit 1
    fi
}

main_menu() {
    TENTACLES_VERSION=v1.0.11
    print_tentacles_menu_header

    # TODO(0): Detect os needs to have its code and menu separated. Until then hardcoding for testing:
    OS_FAMILY="debian" 

    options=()
    if ! is_tentacles_installed; then
        # TODO(2): Make it so that Reset only shows up on a failed or partial install.
        options+=("Install Tentacles" "Reset Tentacles install")
    else
        options+=("Add instance")
        get_instances
        if [ ${#INSTANCE_ARR[@]} -gt 0 ]; then
            options+=("Instance menu")
        fi
        options+=("Install software")

        options+=("Uninstall Tentacles")
    fi
    options+=("Update Tentacles Script" "Quit")

    PS3="${green}Select operation: ${white}"
    select opt in "${options[@]}"; do
        case $opt in
        "Install Tentacles")
            install_tentacles_menu
            break
            ;;
        "Uninstall Tentacles"|"Reset Tentacles install")
            uninstall_tentacles_menu
            break
            ;;
        "Add instance")
            add_instance_menu
            break
            ;;
        "Instance menu")
            echo
            get_instances
            user_select_instance "${green}Select an instance to modify: ${white}" true
            INSTANCE=${SELECTED}
            
            instance_menu
            break
            ;;
        "Utilities")
            utility_menu
            break
            ;;
        "Install software")
            install_menu
            break
            ;;
        "Update Tentacles Script")
            octo_deploy_update
            break
            ;;
        "Quit")
            exit 0
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done
}

install_tentacles_menu() {
    echo "Installing Tentacles"
    
    detect_installs_and_warn
    install_tentacles

    echo "The octavia user has been created with a primary group octoprinters."
    if prompt_confirm "Would you like to join the octoprinters group to have non-sudo access to all the config files?"; then
        join_octoprinters_group
    fi

    main_menu
}

uninstall_tentacles_menu() {
    # TODO(3): More descriptive/red/warning message
    if prompt_confirm "This will delete all of your server data. Are you sure you want to continue? "; then
        uninstall_tentacles
        echo "Tentacles Uninstalled"
    else 
        main_menu
    fi
}

add_instance_menu() {
    user_input_instance_name

    get_instances
    if [ ${#INSTANCE_ARR[@]} -gt 0 ]; then
        # Choose if should use an instance as template
        echo
        echo
        echo "Using a template instance allows you to copy config from one instance to your new instance."
        if prompt_confirm "Use an existing instance as a template?"; then
            get_instances
            user_select_instance "${cyan}Select template instance: ${white}" true
            echo "Using ${SELECTED} as template."
            sudo -u octavia cp /etc/tentacles/${SELECTED}.yaml /etc/tentacles/${INSTANCE}.yaml
            #TODO(1): Clear some config fields stuff? Maybe the udev/camera stuff? Probably the UUIDs need to be regenerated
        fi
    fi

    get_unused_port 5000

    create_instance_config_and_folder

    #Start and enable system processes
    instance_systemctl enable
    instance_systemctl start

    
    instance_menu
}

# TODO(1): Add a systemd actions menu
instance_menu() {
    expect_environment_variables_set INSTANCE
    echo
    echo
    print_instance_menu_header

    options=("Add camera")
    get_cameras_for_instance
    if [ ${#CAMERA_ARR[@]} -gt 0 ]; then
        options+=("Camera menu")
    fi
    if udev_printer_rule_exists; then
        options+=("Remove printer udev rule")
    else
        options+=("Add printer udev rule")
    fi
    if haproxy_printer_rule_exists; then
        options+=("Remove printer haproxy config")
    else
        options+=("Add printer haproxy config")
    fi

    options+=("Backup instance" "Restore instance from backup" "Delete instance" "Return to main menu")

    PS3="${green}Select operation: ${white}"
    select opt in "${options[@]}"; do
        case $opt in
        "Add camera")
            add_camera_menu
            break
            ;;
        "Camera menu")
            get_cameras_for_instance
            user_select_camera "${green}Select camera number to modify: ${white}" true
            CAMERA_NAME=${SELECTED}
            camera_menu
            break
            ;;
        "Add printer udev rule")
            add_printer_udev_menu
            break
            ;;
        "Remove printer udev rule")
            remove_printer_udev_rule
            break
            ;;
        "Add printer haproxy config")
            if is_haproxy_installed; then
                add_haproxy_printer_rule
            else
                echo "haproxy is not installed and set up yet. Use the 'Install software' menu to install it set it up"
            fi
            
            instance_menu
            break
            ;;
        "Remove printer haproxy config")
            remove_haproxy_printer_rule
            break
            ;;
        "Backup instance")
            back_up_instance
            break
            ;;
        "Restore instance from backup")
            restore_menu
            break
            ;;
        "Delete instance")
            echo
            delete_instance_menu
            break
            ;;
        "Return to main menu")
            main_menu
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done
    
    instance_menu
}

delete_instance_menu() {
    expect_environment_variables_set INSTANCE
 
    echo
    echo
    echo "Selected instance to remove: ${INSTANCE}"
    if prompt_confirm "Do you want to remove everything associated with this instance?"; then
        remove_instance
    fi
    main_menu
}

add_camera_menu() {
    expect_environment_variables_set INSTANCE
    echo
    echo

    # TODO(3): Support IP cameras
    options=("Add USB webcam" "Add Pi Cam" "Return to instance menu")

    PS3="${green}Select a camera type to add: ${white}"
    select opt in "${options[@]}"; do
        case $opt in
        "Add USB webcam")
            CAMERA_TYPE="usb"
            break
            ;;
        "Add Pi Cam")
            CAMERA_TYPE="pi"
            break
            ;;
        "Return to instance menu")
            
            instance_menu
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done

    get_installed_streamers
    if [ ${#INSTALLED_STREAMERS[@]} -eq 0 ]; then
        echo "No video streamers installed. Redirecting to the install menu. Install a video streamer then return to add a camera."
        # TODO(3): having to navigate back to adding the camera menu manually is not great
        install_menu
    fi

    options=()
    for streamer in ${INSTALLED_STREAMERS[@]}; do
        if [[ "${CAMERA_TYPE}" != "pi" ]] || [[ "$streamer" != "mjpg-streamer" ]]; then
            options+=("$streamer")
        fi
    done
    options+=("Cancel adding camera")
    echo "If the choice you wish to use is not present, quit and use the install menu to install a streamer."
    PS3="${green}Select a video streamer to provide the camera feed: ${white}"
    select opt in "${options[@]}"; do
        case $opt in
        "uStreamer"|"mjpg-streamer")
            STREAMER=$opt
            break
            ;;
        "Cancel adding camera")
            
            instance_menu
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done

    get_first_free_camera_id_for_instance
    echo "Using first free ID for ${INSTANCE}: ${CAMERA_ID}"
    instance_and_id_to_camera_name
    
    if [[ "${CAMERA_TYPE}" == "usb" ]]; then
        detect_camera
        if [ -n "$NOSERIAL" ] && [ -n "$SERIAL_NUMBER" ]; then
            unset CAM
        fi
        #Failed state. Nothing detected
        if [ -z "$SERIAL_NUMBER" ] && [ -z "$TEMPUSBCAM" ] && [ -z "$BYIDCAM" ]; then
            echo
            echo "${red}No camera was detected during the detection period.${white}"
            echo "Try again or try a different camera."

            return
        fi
        #only BYIDCAM
        if [ -z "$SERIAL_NUMBER" ] && [ -z "$TEMPUSBCAM" ] && [ -n "$BYIDCAM" ]; then
            echo "Camera was only detected as ${cyan}/dev/v4l/by-id${white} entry."
            echo "This will be used as the camera device identifier"
        fi
        #only USB address
        if [ -z "$SERIAL_NUMBER" ] && [ -n "$TEMPUSBCAM" ]; then
            echo "${red}Camera Serial Number not detected${white}"
            echo -e "Camera will be setup with physical USB address of ${cyan}$TEMPUSBCAM.${white}"
            echo "The camera will have to stay plugged into this location."
            USBCAM=$TEMPUSBCAM
        fi
        #serial number
        if [ -n "$SERIAL_NUMBER" ]; then
            echo -e "Camera detected with serial number: ${cyan}$SERIAL_NUMBER ${white}"
            verify_no_duplicate_camera_serial_numbers "$SERIAL_NUMBER"
        fi
        
    else # Pi camera
        echo "Setting up a Pi camera service."
        echo "Please note that mixing this setup with USB cameras may lead to issues."
        echo "Don't expect extensive support for trying to fix these issues."
        echo
    fi

    echo "$SERIAL_NUMBER-$TEMPUSBCAM-$BYIDCAM"
    if [ -n "$SERIAL_NUMBER" ]; then
        echo "adding serial rule"
        add_serial_number_camera_udev_rule
        DEVICE=/dev/$(camera_udev_name)
    elif [ -n "$TEMPUSBCAM" ]; then
        USB_ADDRESS=$TEMPUSBCAM
        add_usb_camera_udev_rule
        DEVICE=/dev/$(camera_udev_name)
    elif [ -n "$BYIDCAM" ]; then
        DEVICE=$BYIDCAM
    else
        echo "Unable to detect camera. Returning to instance menu"
        
        instance_menu
    fi

    echo "Settings can be modified after initial setup in /etc/tentacles/${CAMERA_NAME}.env"
    echo
    while true; do
        echo "Camera Resolution [default: 640x480]:"
        read RESOLUTION
        if [ -z ${RESOLUTION} ]; then
            RESOLUTION="640x480"
            break
        elif [[ ${RESOLUTION} =~ ^[0-9]+x[0-9]+$ ]]; then
            break
        fi
        echo "Invalid resolution"
    done

    echo "Selected camera resolution: ${RESOLUTION}" | log
    echo "Camera Framerate (use 0 for ustreamer hardware) [default: 5]:"
    read FRAMERATE
    if [ -z "$FRAMERATE" ]; then
        FRAMERATE=5
    fi
    echo "Selected camera framerate: $FRAMERATE" | log
    
    get_unused_port 8000

    add_camera

    camera_menu
}

camera_menu() {
    expect_environment_variables_set CAMERA_NAME
    print_camera_menu_header

    options=()
    if haproxy_camera_rule_exists; then
        options+=("Remove camera haproxy config")
    else
        options+=("Add camera haproxy config")
    fi
    options+=("Delete camera" "Return to instance menu")

    PS3="${green}Select operation: ${white}"
    select opt in "${options[@]}"; do
        case $opt in
        "Add camera haproxy config")
            if is_haproxy_installed; then
                add_haproxy_camera_rule
                if prompt_confirm "Instance must be restarted for settings to take effect. Restart now?"; then
                    instance_systemctl restart
                fi
                camera_menu
            else
                echo "haproxy is not yet installed. Redirecting you to the install menu. You can return to this menu to add the rule after installing haproxy."
                install_menu
            fi
            break
            ;;
        "Remove camera haproxy config")
            remove_haproxy_camera_rule
            if prompt_confirm "Instance must be restarted for settings to take effect. Restart now?"; then
                instance_systemctl restart
            fi
            camera_menu
            break
            ;;
        "Delete camera")
            if prompt_confirm "Are you sure you want to delete this camera?"; then
                remove_camera_menu
            fi
            break
            ;;
        "Return to instance menu")
            break;
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done
}

remove_camera_menu() {
    expect_environment_variables_set CAMERA_NAME
    echo "Removing udev, service files, and haproxy entry for ${CAMERA_NAME}"
    remove_camera
    main_menu
}

add_printer_udev_menu() {
    detect_printer

    if [ -n "$SERIAL_NUMBER" ]; then
        add_serial_number_printer_udev_rule
    elif [ -n "$USB_ADDRESS" ]; then
        add_usb_printer_udev_rule
    else
        # TODO(2): better message.
        echo "Unknown state. Shouldnt be possible to get here."
    fi

    main_menu
}

restore_menu() {
    echo
    echo "Selected instance to restore: ${INSTANCE}"
    PS3="${green}Select backup to restore: ${white}"
    readarray -t options < <(ls /usr/local/instance_backup/${INSTANCE}_backup_*.zip)
    options+=("Quit")
    select zipfile in "${options[@]}"; do
        if [ "$zipfile" == Quit ]; then
            main_menu
        fi

        echo "Selected ${INSTANCE} to restore"
        restore ${INSTANCE} $zipfile
        main_menu
    done
}

install_menu() {
    echo "Currently installed Tentacles dependencies:"

    options=()
    printf "%-20s: %s\n" "Octoprint" "/opt/octoprint"
    if is_haproxy_installed; then
        printf "%-20s: %s\n" "HAProxy" $(which haproxy)
        options+=("Uninstall HAProxy")
    else
        printf "%-20s: %s\n" "HAProxy" "Not installed"
        options+=("Install HAProxy")
    fi
    if ! is_ustreamer_installed && ! is_mjpg_streamer_installed; then
        printf "%-20s: %s\n" "Camera Streamers" "None"
    else
        printf "%-20s: %s\n" "Camera Streamers"
    fi
    if is_ustreamer_installed; then
        printf "%-20s: %s\n" "- uStreamer" "/opt/ustreamer"
        options+=("Uninstall uStreamer")
    else
        options+=("Install uStreamer")
    fi
    if is_mjpg_streamer_installed; then
        printf "%-20s: %s\n" "- mjpg-streamer" "/opt/mjpg_streamer"
        options+=("Uninstall mjpg-streamer")
    else
        options+=("Install mjpg-streamer")
    fi

    echo
    echo

    PS3="${green}Select an option: ${white}"
    options+=("Return to main menu")
    select opt in "${options[@]}"; do
        case $opt in
        "Install HAProxy")
            install_haproxy
            break
            ;;
        "Uninstall HAProxy")
            uninstall_haproxy
            break
            ;;
        "Install uStreamer")
            install_ustreamer
            if is_ustreamer_installed; then
                echo "uStreamer installed successfully"
            else
                echo "${red}WARNING! WARNING! WARNING!${white}"
                echo "uStreamer has not been installed correctly."
            fi
            break
            ;;
        "Uninstall uStreamer")
            uninstall_ustreamer
            break
            ;;
        "Install mjpg-streamer")
            install_mjpg_streamer
            if is_ustreamer_installed; then
                echo "mjpg-streamer installed successfully"
            else
                echo "${red}WARNING! WARNING! WARNING!${white}"
                echo "mjpg-streamer has not been installed correctly."
            fi
            break
            ;;
        "Uninstall mjpg-streamer")
            uninstall_mjpg_streamer
            break
            ;;
        "Return to main menu")
            main_menu
            break
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done
    install_menu
}
