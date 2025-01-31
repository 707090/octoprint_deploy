#!/bin/bash

# Find the lowest port starting with 5000 that is not already used by an octoprint instance.
get_unused_port() {
    USED_PORTS=($(find /etc/tentacles/ -type f -name "*.env" -exec grep -H "^PORT=" {} \; | awk -F'=' '{print $2}'))
    PORT=$1
    while [[ " ${USED_PORTS[@]} " =~ " ${PORT} " ]]; do
        ((PORT++))
    done
}

# from stackoverflow.com/questions/3231804
prompt_confirm() {
    while true; do
        read -r -n 1 -p "${green}${1:-Continue?}${white} ${yellow}[y/n]${white}: " REPLY
        case $REPLY in
            [yY]) echo ; return 0 ;;
            [nN]) echo ; return 1 ;;
            *) printf " \033[31m %s \n\033[0m" "invalid input"
        esac
    done
}
# from unix.stackexchange.com/questions/391293
log () {
    if [ -z "$1" ]; then
        cat
    else
        printf '%s\n' "$@"
    fi | tee -a "$logfile"
}

#https://gist.github.com/wellsie/56a468a1d53527fec827
has_space () {
    [[ "$1" != "${1%[[:space:]]*}" ]] && return 0 || return 1
}

has-special () {
    [[ "$1" == *['!'@#\$%^\&*()\/\\+]* ]] && return 0 || return 1
}

octo_deploy_update() {
    sudo -u $SUDO_USER git -C $SCRIPTDIR pull
    exit
}


back_up_all() {
    get_instances false
    for instance in "${INSTANCE_ARR[@]}"; do
        echo $instance
        back_up $instance
    done
}

color_systemd_status() {
    if [ "${SYSTEMD_STATUS}" = "active" ]; then
        SYSTEMD_STATUS="${green}${SYSTEMD_STATUS}${white}"
    elif [ "${SYSTEMD_STATUS}" = "activating" ] || [ "${SYSTEMD_STATUS}" = "deactivating" ] || [ "${SYSTEMD_STATUS}" = "reloading" ]; then
        SYSTEMD_STATUS="${green}${SYSTEMD_STATUS}${white}"
    elif [ "${SYSTEMD_STATUS}" = "inactive" ] || [ "${SYSTEMD_STATUS}" = "failed" ] || [ "${SYSTEMD_STATUS}" = "dead" ]; then
        SYSTEMD_STATUS="${red}${SYSTEMD_STATUS}${white}"
    fi
}

# TODO: Revive this
usb_testing() {
    echo
    echo
    echo "Testing printer USB"
    detect_printer
    echo "Detected device at $TEMPUSB"
    echo "Serial Number detected: $UDEV"
    main_menu
}

diagnostic_output() {
    echo "**************************************"
    echo "$1"
    echo "**************************************"
    cat $1

}

# TODO(2): Revive this
diagnostics() {
    logfile='octoprint_deploy_diagnostic.log'
    echo "octoprint_deploy diagnostic information. Please provide ALL output for support help"
    diagnostic_output /etc/octoprint_deploy | log
    diagnostic_output /etc/octoprint_instances | log
    diagnostic_output /etc/octoprint_cameras | log
    diagnostic_output /etc/udev/rules.d/99-octoprint.rules | log
    ls -la /dev/octo* | log
    #get all instance status
    get_instances
    for instance in "${INSTANCE_ARR[@]}"; do
        echo "**************************************" | log
        systemctl status $instance -l --no-pager | log
        #get needed config info
        sudo -u octavia /opt/octoprint/bin/octoprint --basedir=/home/octavia/.${INSTANCE} config get plugins.classicwebcam | log
        #sudo -u octavia /opt/octoprint/bin/octoprint --basedir=/home/octavia/.${INSTANCE} config get plugins.classicwebcam.snapshot | log
        sudo -u octavia /opt/octoprint/bin/octoprint --basedir=/home/octavia/.${INSTANCE} config get webcam | log

        #get instance cam status
        get_cameras_for_instance
        for camera in "${CAMERA_ARR[@]}"; do
            echo "**************************************" | log
            systemctl status $camera -l --no-pager | log
        done
    done

    #get haproxy status
    echo "**************************************" | log
    systemctl status haproxy -l --no-pager | log
    logfile='octoprint_deploy.log'
    main_menu
}

expect_environment_variables_set() {
    local missing_vars=()

    # Loop through each provided variable
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    # TODO(2): Extract this out to a function called unwind_stack. Also reverse its direction and add more error description
    # If there are missing variables, print them and return non-zero exit code
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "Call stack:"
        # Loop through the call stack
        for i in "${!FUNCNAME[@]}"; do
            # Only print relevant entries (excluding the current function and script)
            if [[ "${FUNCNAME[$i]}" != "check_env_vars" && "${BASH_SOURCE[$i]}" != "$0" ]]; then
                echo "${BASH_SOURCE[$i]} - ${FUNCNAME[$i]}"
            fi
        done

        echo "The following environment variables are missing or unset:"
        for var in "${missing_vars[@]}"; do
            echo "- $var"
        done
        return 1
    else
        return 0
    fi
}

# TODO: manually checking for values true/false/numbers might not encompass all possibilities the config cares about
# TODO: implement array items being something other than strings
# TODO: Im not sure slurp is really the right approach here, I just want a value to work with even if the file is empty
# TODO: Make an argument that only fills the default fields if they are empty
update_config() {
    expect_environment_variables_set INSTANCE
    # Ensure the correct number of arguments (key=value pairs)
    if [ "$#" -eq 0 ]; then
        echo "update_config error: No configuration values provided."
        return 1
    fi

    # Initialize the yq command
    local yq_command="sudo -u octavia /opt/octoprint/bin/yq --slurp --yaml-output --in-place \".[0] // {}"

    # Loop through the arguments and construct the `yq` expressions
    for pair in "$@"; do
        IFS='=' read -r key value <<< "$pair"
        # Handle arrays
        if [[ "$value" =~ ^\[(.*)\]$ ]]; then
            # Extract the array elements (inside the square brackets)
            array_elements="${BASH_REMATCH[1]}"

            # Process the elements as a list of comma-separated values
            IFS=',' read -ra elements <<< "$array_elements"
            array_values=""
            for element in "${elements[@]}"; do
                # Strip leading/trailing spaces from array elements
                element=$(echo "$element" | xargs)
                
                # Escape special characters in each array element and add quotes
                element=$(echo "$element" | sed 's/\&/\\&/g; s/\$/\\\$/g; s/"/\\"/g')
                array_values+="\\\"$element\\\", "
            done

            # Remove the trailing comma and space
            array_values=${array_values%, }

            # Build the yq expression for the array
            yq_command+=" | .${key} = [ $array_values ]"
        # Check if value is true, false, or a number (no quotes if so)
        elif [[ "$value" =~ ^(true|false)$ ]] || [[ "$value" =~ ^-?[0-9]+$ ]]; then
            # No quotes if it's a boolean or number
            yq_command+=" | .${key} = ${value}"
        else
            # Escape special characters and add quotes for strings
            value=$(echo "$value" | sed 's/\&/\\&/g; s/\$/\\\$/g; s/"/\\"/g')
            yq_command+=" | .${key} = \\\"${value}\\\""
        fi
    done

    # Append the target YAML file and execute the final command
    yq_command+="\" /etc/tentacles/${INSTANCE}.yaml"
    eval "$yq_command"
}