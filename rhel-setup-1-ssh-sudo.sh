#!/usr/bin/bash -x
#-------------------------
# Description
#
# Set up a few authentication and authorization things on two machines.
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

create_control_working_directory () {
    log_this "create working directory $CONTROL_WORK_DIR"
    mkdir $CONTROL_WORK_DIR
    cd $CONTROL_WORK_DIR
}

create_control_rsa_keys () {
    if [[ -f $CONTROL_HOME/.ssh/id_rsa ]]; then
        log_this "RSA private key already exists in control $CONTROL_NODE_NAME $CONTROL_HOME/.ssh/id_rsa"
        return
    fi
    log_this "generate control RSA keys for $CONTROL_USER_NAME"
     ssh-keygen -f $CONTROL_HOME/.ssh/id_rsa -q -N ""
    cat $CONTROL_HOME/.ssh/id_rsa.pub | tee -a $CONTROL_HOME/.ssh/authorized_keys 
}

trust_managed_host_key_and_ip () {
    log_this "copy key from $MANAGED_NODE_IP to control $CONTROL_NODE_NAME $CONTROL_HOME/.ssh/known_hosts file"
    # backup known_hosts
    cp $CONTROL_HOME/.ssh/known_hosts $CONTROL_WORK_DIR/known_hosts-before-ips
    # get managed host key
    LINE=$(ssh-keyscan -t ssh-ed25519 $MANAGED_NODE_IP)
    # add line if not already there
    grep -qxF "$LINE" $CONTROL_HOME/.ssh/known_hosts || echo "$LINE" | tee -a $CONTROL_HOME/.ssh/known_hosts
}

# Copy RSA public keys from here to new machinejs for passwordless login.
# Type in your login password on each host.
# After this, no login password is required. 
# If typing is annoying, see this blog post for an alternative.
#   https://www.redhat.com/sysadmin/ssh-automation-sshpass
push_rsa_pubkey () {
    log_this "copy RSA public key from control $CONTROL_NODE_NAME to managed $MANAGED_NODE_IP for passwordless login"
    ssh-copy-id $MANAGED_USER_NAME@$MANAGED_NODE_IP
}

push_passwordless_sudo () {
    log_this "configure managed $MANAGED_NODE_IP sudo for passwordless privilege escalation"
    CONTROL_TMP_FILE=$CONTROL_WORK_DIR/sudoers-$MANAGED_USER_NAME
    MANAGED_TMP_FILE=$MANAGED_WORK_DIR/sudoers-$MANAGED_USER_NAME
    echo "$MANAGED_USER_NAME      ALL=(ALL)       NOPASSWD: ALL" > $CONTROL_TMP_FILE
    scp $CONTROL_TMP_FILE $MANAGED_USER_NAME@$MANAGED_NODE_IP:$MANAGED_TMP_FILE
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_IP sudo cp $MANAGED_TMP_FILE /etc/sudoers.d/$MANAGED_USER_NAME
    # clean up
    # rm $CONTROL_TMP_FILE
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_IP rm $MANAGED_TMP_FILE
}

update_control_hosts_file () {
    log_this "add managed $MANAGED_NODE_IP to control $CONTROL_NODE_NAME /etc/hosts file"
    # get a copy for backup
    scp $MANAGED_USER_NAME@$MANAGED_NODE_IP:/etc/hosts $CONTROL_WORK_DIR/hosts-$MANAGED_NODE_IP
    # add lines if not already there
    LINE="$MANAGED_NODE_IP  $MANAGED_NODE_FQDN"
    grep -qxF "$LINE" /etc/hosts || echo "$LINE" | sudo tee -a /etc/hosts
}

trust_managed_host_key_and_name () {
    log_this "copy keys from managed $MANAGED_NODE_FQDN to control $CONTROL_NODE_NAME $CONTROL_HOME/.ssh/known_hosts file"
    # get a copy for backup
    cp $CONTROL_HOME/.ssh/known_hosts $CONTROL_WORK_DIR/known_hosts-before-names
    # add line if not already there
    LINE=$(ssh-keyscan -t ssh-ed25519 $MANAGED_NODE_FQDN)
    grep -qxF "$LINE" $CONTROL_HOME/.ssh/known_hosts || echo "$LINE" | tee -a $CONTROL_HOME/.ssh/known_hosts
}

set_managed_hostname () {
    log_this "set host name in $MANAGED_NODE_IP to $MANAGED_NODE_FQDN"
     ssh $MANAGED_USER_NAME@$MANAGED_NODE_IP sudo hostnamectl set-hostname $MANAGED_NODE_FQDN
}

# display FQDN, not just hostname. 
# Two ways to do this
# oldskool: 
#   Redefine $PS1. 
#   Add colors. See https://tldp.org/HOWTO/Bash-Prompt-HOWTO/x329.html
#   PS1='[\u@\H \W]\$ '
# newskool:
#   $PS1 is made up of many variables. Change only the hostname. 
#   PROMPT_USERHOST='\u@\H'
#   see   
#   /usr/share/doc/bash-color-prompt/README.md
#   /etc/profile.d/bash-color-prompt.sh
change_managed_prompt () {
    log_this "change PS1 in managed $MANAGED_NODE_FQDN $MANAGED_HOME/.bashrc"
    # get a copy for backup
    scp $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_HOME/.bashrc $CONTROL_WORK_DIR/bashrc-$MANAGED_NODE_FQDN
    # add line if not already there
    LINE="PS1='[\u@\H \W]\$ '"      # oldskool
    LINE="PROMPT_USERHOST='\u@\H'"  # newskool
    # for me
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN "grep -qxF \"$LINE\" $MANAGED_HOME/.bashrc || echo \"$LINE\" | tee -a $MANAGED_HOME/.bashrc"
    # for root
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN "sudo grep -qxF \"$LINE\" /root/.bashrc  || echo \"$LINE\" | sudo tee -a /root/.bashrc"
}

create_managed_working_directory () {
    log_this "create a working directory $MANAGED_WORK_DIR on managed $MANAGED_NODE_IP"
    ssh -o ConnectTimeout=10 $MANAGED_USER_NAME@$MANAGED_NODE_IP mkdir -p $MANAGED_WORK_DIR
    if [ $? -ne 0 ]; then
        log_this "error, failed to connect to $MANAGED_NODE_IP. Does config file $CONFIG_FILE have the correct IP address?"
        exit 3
    fi

}


# SSH - worse security
# add root keys so root can log in remotely
root_login_to_managed () {
    log_this "allow remote root login on $MANAGED_NODE_FQDN"
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo cp $MANAGED_HOME/.ssh/authorized_keys /root/.ssh/authorized_keys
}


# SSH - better security
# Use key-based login only, disable password login
# For more information, run 'man sshd_config'
restrict_ssh_auth_on_managed () {
    log_this "restrict SSH authentication to key only on $MANAGED_NODE_FQDN"
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN "sudo grep -qxF 'AuthenticationMethods publickey' /etc/ssh/sshd_config  || echo 'AuthenticationMethods publickey' | sudo tee -a /etc/ssh/sshd_config"
}


log_this () {
    echo
    echo -n $(date)
    echo "  $1"
}

#-------------------------
# main

# at first, we login using the IPv4 address
# on control node
create_control_working_directory
create_control_rsa_keys  
# on managed node
create_managed_working_directory
trust_managed_host_key_and_ip
push_rsa_pubkey
push_passwordless_sudo
# after some config, we can login using the FQDN
update_control_hosts_file
trust_managed_host_key_and_name
set_managed_hostname
change_managed_prompt
root_login_to_managed
restrict_ssh_auth_on_managed
