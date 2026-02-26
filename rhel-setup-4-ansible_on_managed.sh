#!/usr/bin/bash -x
#-------------------------
# Description
#
# Get ready for Ansible. 
#     control node --> managed node
# Find the code on Github here. 
#   https://github.com/nickhardiman/script-rhel-setup
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

setup_managed_ansible_user_account() {
    log_this "add an Ansible user account"
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo useradd $MANAGED_ANSIBLE_NAME
}


push_ansible_pubkey_to_managed() {
     CONTROL_ANSIBLE_PUBLIC_KEY=$(<$CONTROL_HOME/.ssh/ansible-key.pub)
    log_this "copy $CONTROL_ANSIBLE_NAME public key from here to $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:/home/$MANAGED_ANSIBLE_NAME/.ssh/authorized_keys"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN << EOF
            sudo --user=$MANAGED_ANSIBLE_NAME mkdir      /home/$MANAGED_ANSIBLE_NAME/.ssh
            sudo --user=$MANAGED_ANSIBLE_NAME chmod 0700 /home/$MANAGED_ANSIBLE_NAME/.ssh
            sudo --user=$MANAGED_ANSIBLE_NAME touch      /home/$MANAGED_ANSIBLE_NAME/.ssh/authorized_keys
            sudo grep -qxF "$CONTROL_ANSIBLE_PUBLIC_KEY" /home/$MANAGED_ANSIBLE_NAME/.ssh/authorized_keys || echo "$CONTROL_ANSIBLE_PUBLIC_KEY" | sudo tee -a /home/$MANAGED_ANSIBLE_NAME/.ssh/authorized_keys
EOF
}


push_ansible_passwordless_sudo () {
    log_this "configure managed $MANAGED_NODE_IP sudo for passwordless privilege escalation"
    CONTROL_TMP_FILE=$CONTROL_WORK_DIR/sudoers-$MANAGED_ANSIBLE_NAME
    MANAGED_TMP_FILE=$MANAGED_WORK_DIR/sudoers-$MANAGED_ANSIBLE_NAME
    echo "$MANAGED_ANSIBLE_NAME      ALL=(ALL)       NOPASSWD: ALL" > $CONTROL_TMP_FILE
    scp $CONTROL_TMP_FILE $MANAGED_USER_NAME@$MANAGED_NODE_IP:$MANAGED_TMP_FILE
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo cp $MANAGED_TMP_FILE /etc/sudoers.d/$MANAGED_ANSIBLE_NAME
    # clean up
    # rm $CONTROL_TMP_FILE
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_IP rm $MANAGED_TMP_FILE
}


# known_hosts copy removed the need for this option
#             -o StrictHostKeyChecking=no
check_ansible_user() {
    log_this "check key-based login and passwordless sudo for account $MANAGED_ANSIBLE_NAME@$MANAGED_NODE_FQDN"
    ssh \
        -i $CONTROL_HOME/.ssh/ansible-key.priv \
        $MANAGED_ANSIBLE_NAME@$MANAGED_NODE_FQDN  \
        sudo id
    res_ssh=$?
    if [ $res_ssh -ne 0 ]; then 
        echo "error: can't SSH and sudo with $MANAGED_ANSIBLE_NAME"
        exit $res_ssh
    fi
}


log_this () {
    echo
    echo -n $(date)
    echo "  $1"
}


#-------------------------
# main

cd $CONTROL_WORK_DIR || exit 1
setup_managed_ansible_user_account
push_ansible_pubkey_to_managed
push_ansible_passwordless_sudo
