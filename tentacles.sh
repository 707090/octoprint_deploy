#!/bin/bash

# All operations must be with root/sudo
if (( $EUID != 0 )); then
    echo "Please run with sudo"
    exit
fi

# This is a weak check, but will catch most cases
if [ ! $SUDO_USER ]; then
    echo "You should not run this script as root. Use sudo as a normal user"
    exit
fi

# initiate logging
logfile='octoprint_deploy.log'
SCRIPT_DIR=$(dirname $(readlink -f $0))
source ${SCRIPT_DIR}/plugins.sh
source ${SCRIPT_DIR}/prepare.sh
source ${SCRIPT_DIR}/instance.sh
source ${SCRIPT_DIR}/util.sh
source ${SCRIPT_DIR}/menu.sh
source ${SCRIPT_DIR}/cameras.sh
source ${SCRIPT_DIR}/haproxy.sh
source ${SCRIPT_DIR}/install.sh

#command line arguments
if [ "$1" == remove ]; then
    uninstall_tentacles
fi

if [ "$1" == restart_all ]; then
    restart_all
fi

if [ "$1" == backup ]; then
    back_up_all
fi

if [ "$1" == noserial ]; then
    NOSERIAL=1
fi
#let's make it possible to inject any function directly
if [ "$1" == f ]; then
    $2
fi
main_menu
