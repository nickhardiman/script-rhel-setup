#!/usr/bin/bash -x
#-------------------------
# Description
#
# Configure a RHEL machine by setting up SSH, sudo, Ansible and other things.
# Run this Bash script on one machine (the control node) to configure another machine (the managed node).
#     control node --> managed node
# The control node is probably your local workstation. 
# The managed node is probably a remote machine with a fresh install of the RHEL OS. 
# 
# Find the code on Github here. 
#   https://github.com/nickhardiman/script-rhel-setup
#
#-------------------------
# Prerequisites
# 
# Install RHEL. A minimal install is fine. 
# Set a root password.
# Create a user with admin privileges (in the wheel group).
# Set a user password.
# Find out what IP address your DHCP server assigned to the host.
#
#-------------------------
# What the script does
#
# Configure a RHEL machine by setting up SSH, sudo, Ansible and other things.
# This script runs on one machine and configures another machine.
# The control node where the script runs is probably your workstation. 
# The managed node that the script configures is a freshly installed RHEL machine.
#
# Code runs on workstation and uses SSH to run many commands on the new RHEL machine. 
#     rhel-setup.sh --(SSH)--> many commands
# Code creates or adds to these files. 
#     control node
#       copy backups to $HOME/$CONTROL_WORK_DIR
#       add remote name and address in /etc/hosts
#       create private key in $HOME/.ssh/id_rsa (if not already there)
#       create public key in $HOME/.ssh/id_rsa.pub
#       add remote host key to $HOME/.ssh/known_hosts
#     managed node
#       Define a new prompt in $HOME/.bashrc
#       Add control's $HOME/.ssh/authorized_keys
#       /etc/sudoers.d/$USER
#
# This bash script runs and pulls in more bash scripts.
# This script and the ones it calls do a whole heap of unsafe things, 
# so this is for home lab dev use only.
#
# Set up a few authentication and authorization things.
# * Add key-based SSH login.
# * Add passwordless sudo.
# * Display FQDN in the prompt. By default, only the host name is shown eg. "[nick@host ~]$ ".
# 
# Uses environment variables
# A few env vars are used here.
# For me, the values are:
#   HOME=/home/nick
#   USER=nick
#
#
# Install applications.
# * Ansible on the control node
# * KVM hypervisor on the three site hosts
# * supporting services on site3
#
#-------------------------
# Instructions
#
# SSH to the control node.
# Download this file and the config file from Github to your home directory.
#    curl -O https://raw.githubusercontent.com/nickhardiman/script-rhel-setup/main/rhel-setup.sh
#    curl -O https://raw.githubusercontent.com/nickhardiman/script-rhel-setup/main/rhel-setup.cfg
# Edit rhel-setup.cfg and change my details to yours.
#     Find out what IP addresses your ISP's router assigned to the hosts.
#     Add the IP adresses.
# Run the script. 
#     bash rhel-setup.sh    
# SSH asks you to confirm host key and enter your password. 
#     This key is not known by any other names.
#     Are you sure you want to continue connecting (yes/no/[fingerprint])? 
#     Warning: Permanently added '1.2.3.4' (ED25519) to the list of known hosts.
#     nick@1.2.3.4's password: 
# Type in your user password.
#
#-------------------------
# Variables
#
CONFIG_FILE=~/rhel-setup.cfg
source $CONFIG_FILE
#
#-------------------------
# functions
#

log_this () {
    [[ "$QUIET" -eq 0 ]] && return
    echo -n $(date)
    echo "  $1"
}

usage() {
    echo "Usage: $0 [-h|-v|-t]"
    echo "Set up a new RHEL host."
    echo "Edit the config file $CONFIG_FILE, then run this on a control node to set up a managed node."
    echo "Options:"
    echo "  -h  Help, show this help message"
    echo "  -q  Quiet, do not log activity"
    echo "  -t  Test, do not change anything, just show what would be done"
    echo "Exit codes:"
    echo "  0  Success"
    echo "  1  Usage"
    echo "  2  Download failed"
    exit 1
}


read_cli_options() {
    while getopts ":hqt" option; do
        case $option in
            h) # display help
                usage
                ;;
            q) # QUIET output
                QUIET=0
                ;;
            t) # test only, do not change anything
                QUIET=1
                TEST=0
                ;;
            \?) # Invalid option
                echo "$0 error:   Invalid option: -$OPTARG" >&2
                exit 6
                ;;
        esac
    done
}

download_from_repo() {
    log_this "download $1 from Github to $(pwd)"
    curl --silent --fail --remote-name https://raw.githubusercontent.com/nickhardiman/script-rhel-setup/main/$1
    if [ $? -ne 0 ]
    then
        log_this "error, failed to download $1 from Github"
        exit 2
    fi
}

# !!! reboot breaks flow
reboot_control () {
    log_this "reboot $CONTROL_NODE_NAME if required"
    sudo dnf needs-restarting
    if [ $? -ne 0 ]
    then
        sudo systemctl reboot
    fi
}

reboot_managed () {
    log_this "reboot $MANAGED_NODE_FQDN if required"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_IP sudo dnf needs-restarting
    if [ $? -ne 0 ]
    then
        ssh $MANAGED_USER_NAME@$MANAGED_NODE_IP sudo systemctl reboot
    fi
}



#---------
# Main script starts here
# Set defaults
# Process command line options
# Download scripts from Github
# Run the scripts

# 0 is true, 1 is false
QUIET=1     # 0=silent, 1=noisy
TEST=1      # 0=safe, 1=dangerous
SCRIPTS=" \
  rhel-setup-1-control-node.sh \
  rhel-setup-2-managed-node.sh \
  rhel-setup-3-ansible_on_control.sh \
  rhel-setup-4-ansible_on_managed.sh \
  rhel-setup-5-ansible-vault.sh \
  rhel-setup-6-ansible-playbook-test.sh \
"

read_cli_options "$@"

for FILE in $SCRIPTS
do
    download_from_repo $FILE
done

for FILE in $SCRIPTS
do
    log_this "run $FILE"
    bash ./$FILE
done

log_this "setup done"
reboot_managed
reboot_control
# if control node reboots, the script ends here
exit 0         
#---------
# End of script
