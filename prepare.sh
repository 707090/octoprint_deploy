#!/bin/bash
detect_installs_and_warn() {
    EXISTING_HOME_OCTOPRINT_INSTALL=$(find /home/$SUDO_USER/ -type f -executable -print | grep "bin/octoprint")
    if [ -n "$EXISTING_HOME_OCTOPRINT_INSTALL" ]; then
        # TODO: Allow importing existing configurations and plugins
        echo "OctoPrint binary found at $EXISTING_HOME_OCTOPRINT_INSTALL. Note that Tentacles does a fresh install of octoprint as a part of its installation. This means any modifications to your existing virtual environment will not be saved and must be redone."
    fi
    echo "Looking for existing OctoPrint systemd files....."
    readarray -t EXISTING_SYSTEMD_SERVICES < <(fgrep -l bin/octoprint /etc/systemd/system/*.service)
    if [ ${#EXISTING_SYSTEMD_SERVICES[@]} -gt 0 ]; then
        echo "Existing systemd service found for octoprint. This will no longer be needed as octoprint will install its own systemd service. Keeping a systemd service outside of Tentacles running could cause port conflicts."
    fi
}

deb_packages() {
    #All extra packages needed can be added here for deb based systems. Only available will be selected.
    apt-cache --generate pkgnames |
        grep --line-regexp --fixed-strings \
            -e make \
            -e v4l-utils \
            -e python-is-python3 \
            -e python3-venv \
            -e python3.9-venv \
            -e python3.10-venv \
            -e python3.11-venv \
            -e python3.11-dev \
            -e virtualenv \
            -e python3-dev \
            -e build-essential \
            -e python3-setuptools \
            -e libyaml-dev \
            -e python3-pip \
            -e cmake \
            -e libjpeg8-dev \
            -e libjpeg62-turbo-dev \
            -e gcc \
            -e g++ \
            -e libevent-dev \
            -e libjpeg-dev \
            -e libbsd-dev \
            -e ffmpeg \
            -e uuid-runtime -e ssh -e libffi-dev -e haproxy -e libavformat-dev -e libavutil-dev -e libavcodec-dev -e libcamera-dev -e libcamera-tools -e libcamera-v4l2 -e liblivemedia-dev -e v4l-utils -e pkg-config -e xxd -e build-essential -e libssl-dev -e rsync | xargs apt-get install -y

    #pacakges to REMOVE go here
    apt-cache --generate pkgnames |
        grep --line-regexp --fixed-strings \
            -e brltty |
        xargs apt-get remove -y

}

dnf_packages() {
    #untested
    dnf install -y \
        gcc \
        python3-devel \
        cmake \
        libjpeg-turbo-devel \
        libbsd-devel \
        libevent-devel \
        haproxy \
        openssh \
        openssh-server \
        libffi-devel \
        libcamera-devel \
        v4l-utils \
        xxd \
        openssl-devel \
        rsync

}

pacman_packages() {
    pacman -S --noconfirm --needed \
        make \
        cmake \
        python \
        python-virtualenv \
        libyaml \
        python-pip \
        libjpeg-turbo \
        python-yaml \
        python-setuptools \
        libffi \
        ffmpeg \
        gcc \
        libevent \
        libbsd \
        openssh \
        haproxy \
        v4l-utils \
        rsync
}

zypper_packages() {
    zypper in -y \
        gcc \
        python3-devel \
        cmake \
        libjpeg-devel \
        libbsd-devel \
        libevent-devel \
        haproxy \
        openssh \
        openssh-server \
        libffi-devel \
        v4l-utils \
        xxd \
        libopenssl-devel \
        rsync

}


prepare_debian_based() {
    apt-get update >/dev/null
    PYV=$(python3 -c"import sys; print(sys.version_info.minor)")
    deb_packages
}

prepare_rhel_based() {
    echo "Fedora and variants have SELinux enabled by default."
    echo "This causes a fair bit of trouble for running OctoPrint."
    echo "You have the option of disabling this now."
    if prompt_confirm "${green}Disable SELinux?${white}"; then
        sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config
        echo "${magenta}You will need to reboot after system preparation.${white}"
    fi
    systemctl enable sshd.service
    PYV=$(python3 -c"import sys; print(sys.version_info.minor)")
    if [ $PYV -gt 11 ]; then
        dnf -y install python3.11-devel
        PYVERSION='python3.11'
    fi
    dnf_packages
}

prepare_arch_based() {
    pacman_packages
}

prepare_suse_based() {
    zypper_packages
    systemctl enable sshd.service
}

prepare() {
    echo
    echo

    detect_os

    create_tentacles_user
    echo "This will install necessary packages, install OctoPrint and setup an instance."
    #install packages
    PYVERSION="python3"

    case $OS_FAMILY in
    "debian")
        prepare_debian_based
        break
        ;;
    "rhel")
        prepare_rhel_based
        break
        ;;
    "arch")
        prepare_arch_based
        break
        ;;
    "suse")
        prepare_suse_based
        break
        ;;
    *) echo "invalid option $REPLY" ;;
    esac

    # TODO(1): add the ability to import existing instance(s) to Tentacles

    echo "Enabling ssh server..."
    systemctl enable ssh.service
    
    # TODO(2): maybe check if octavia exists and jump to remove-everything if so?. Or maybe generally add more "failed install" logic checks

    echo "Creating ${green}octavia${white} user and ${green}octoprinters${white} group"
    echo "Adding octavia user to dialout and video groups"
    echo "Creating octavia user directories. The config for your Tentacles (OctoPrint instances) can be found in ${cyan}/etc/tentacles/${white}, and the server folders can be found in ${cyan}/usr/share/tentacles/${white}"
    echo "Adding the octavia user as a passwordless sudoer of systemctl and reboot at ${cyan}/etc/sudoers.d/999_octoprint_sudoer${white}"
    create_tentacles_user

    if prompt_confirm "Would you like to be added to the octoprinters group?"; then
        echo "Adding $SUDO_USER to octoprinters group"
        join_octoprint_group
    fi

    echo "Installing OctoPrint virtual environment in /opt/octoprint"
    # TODO(3): add loading bar/wheel
    install_octoprint

    #Check to verify that OctoPrint binary is installed
    if is_octoprint_installed; then
        echo "${cyan}OctoPrint apppears to have been installed successfully${white}"
    else
        echo "${red}WARNING! WARNING! WARNING!${white}"
        echo "OctoPrint has not been installed correctly."
        echo "Please answer Y to remove everything and try running prepare system again."
        uninstall_tentacles
        exit
    fi

    #Create first instance
    echo
    echo
    echo
    echo
    echo "${cyan}It is time to create your first OctoPrint instance!!!${white}"
    add_instance_menu
    echo
    echo
    if prompt_confirm "Would you like to install recommended plugins now?"; then
        plugin_menu
    fi
    main_menu
}

#TODO(1): Move this functionality to the tentacles install function
firstrun_install() {
    echo
    echo
    echo 'The first instance can be configured at this time.'
    echo 'This includes setting up the admin user and finishing the startup wizards.'
    echo
    echo
    if prompt_confirm "Do you want to setup your admin user now?"; then
        while true; do
            echo 'Enter admin user name (no spaces): '
            read OCTOADMIN
            if [ -z "$OCTOADMIN" ]; then
                echo -e "No admin user given! Defaulting to: \033[0;31moctoadmin\033[0m"
                OCTOADMIN=octoadmin
            fi
            if ! has_space "$OCTOADMIN"; then
                break
            else
                echo "Admin user name must not have spaces."
            fi
        done
        echo "Admin user: ${cyan}$OCTOADMIN${white}"

        while true; do
            echo 'Enter admin user password (no spaces): '
            read OCTOPASS
            if [ -z "$OCTOPASS" ]; then
                echo -e "No password given! Defaulting to: ${cyan}fooselrulz${white}. Please CHANGE this."
                OCTOPASS=fooselrulz
            fi

            if ! has_space "$OCTOPASS"; then
                break
            else
                echo "Admin password cannot contain spaces"
            fi

        done
        echo "Admin password: ${cyan}$OCTOPASS${white}"
        sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE user add $OCTOADMIN --password $OCTOPASS --admin
    fi

    if [ -n "$OCTOADMIN" ]; then
        echo
        echo
        echo "The script can complete the first run wizards now."
        echo "For more information on these, see the OctoPrint website."
        echo "It is standard to accept this, as no identifying information is exposed through their usage."
        echo
        echo
        if prompt_confirm "Complete first run wizards now?"; then
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set server.firstRun false --bool
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set server.seenWizards.backup null
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set server.seenWizards.corewizard 4 --int
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set server.onlineCheck.enabled true --bool
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set server.pluginBlacklist.enabled true --bool
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set plugins.tracking.enabled true --bool
            sudo -u octavia /opt/octoprint/bin/octoprint --basedir $BASE config set printerProfiles.default _default
        fi
    fi

    echo "Restarting instance....."
    instance_systemctl restart
}
