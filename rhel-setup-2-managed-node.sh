#!/usr/bin/bash -x
#-------------------------
# Description
#
# Customize RHEL on the managed node
#     control node --> managed node
# Find the code on Github here. 
#   https://github.com/nickhardiman/script-rhel-setup
#
# Lots of ssh and sudo here. 
# use this format
#   ssh $HOST /usr/bin/bash << EOF 
# using 'ssh $HOST << EOF'  causes error
#   Pseudo-terminal will not be allocated because stdin is not a terminal.
#
#-------------------------
# Variables
#
CONFIG_FILE=./rhel-setup.cfg
source $CONFIG_FILE
#
#-------------------------
# functions

# Enable nested virtualization? 
# In /etc/modprobe.d/kvm.conf 
# options kvm_amd nested=1



ping_ip () {
    log_this "ping from control $CONTROL_NODE_NAME to managed $MANAGED_NODE_IP"
    ping $VERBOSE_FLAG -c1 $MANAGED_NODE_IP
    if [ $? -ne 0 ]; then
        log_this "error, failed to connect to $MANAGED_NODE_IP. Does config file $CONFIG_FILE have the correct IP address?"
        exit 3
    fi
}


ping_fqdn () {
    log_this "ping from control $CONTROL_NODE_NAME to managed $MANAGED_NODE_FQDN"
    ping $VERBOSE_FLAG -c1 $MANAGED_NODE_FQDN
    if [ $? -ne 0 ]; then
        log_this "error, failed to connect to $MANAGED_NODE_FQDN"
        exit 4
    fi
}


ssh_to_ip () {
    log_this "check SSH from control $CONTROL_NODE_NAME to managed $MANAGED_NODE_IP"
    ssh \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=10 \
      $MANAGED_USER_NAME@$MANAGED_NODE_IP id
    if [ $? -ne 0 ]; then
        log_this "error, failed to connect to $MANAGED_NODE_IP. Does config file $CONFIG_FILE have the correct IP address?"
        exit 5
    fi
}


trust_managed_host_key_and_ip () {
    log_this "copy key from $MANAGED_NODE_IP to control $CONTROL_NODE_NAME $CONTROL_HOME/.ssh/known_hosts file"
    # backup known_hosts
    cp $CONTROL_HOME/.ssh/known_hosts $CONTROL_WORK_DIR/known_hosts-control-before-ips
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
    log_this "copy public key from control $CONTROL_NODE_NAME to managed $MANAGED_USER_NAME@$MANAGED_NODE_IP for passwordless login"
    /usr/bin/sshpass $VERBOSE_FLAG -p "$MANAGED_USER_PASSWORD" \
      /usr/bin/ssh-copy-id $MANAGED_USER_NAME@$MANAGED_NODE_IP
}


# ------
# no more SSH password

create_managed_working_directory () {
    log_this "create a working directory $MANAGED_WORK_DIR on managed $MANAGED_NODE_IP"
    ssh $VERBOSE_FLAG $MANAGED_USER_NAME@$MANAGED_NODE_IP \
      mkdir -p $MANAGED_WORK_DIR
    if [ $? -ne 0 ]; then
        log_this "error, failed to create directory $MANAGED_NODE_IP:$MANAGED_WORK_DIR"
        exit 4
    fi
}


push_passwordless_sudo () {
    log_this "configure managed $MANAGED_NODE_IP sudo for passwordless privilege escalation"
    CONTROL_TMP_FILE=$CONTROL_WORK_DIR/sudoers-$MANAGED_USER_NAME
    MANAGED_TMP_FILE=$MANAGED_WORK_DIR/sudoers-$MANAGED_USER_NAME
    echo "$MANAGED_USER_NAME      ALL=(ALL)       NOPASSWD: ALL" > $CONTROL_TMP_FILE
    scp $CONTROL_TMP_FILE $MANAGED_USER_NAME@$MANAGED_NODE_IP:$MANAGED_TMP_FILE
    ssh $VERBOSE_FLAG $MANAGED_USER_NAME@$MANAGED_NODE_IP /usr/bin/bash $BASH_FLAG << EOF
      echo "$MANAGED_USER_PASSWORD" | sudo -S cp $MANAGED_TMP_FILE /etc/sudoers.d/$MANAGED_USER_NAME
EOF
    # clean up
    ssh $VERBOSE_FLAG $MANAGED_USER_NAME@$MANAGED_NODE_IP rm $MANAGED_TMP_FILE
    echo # new line after sudoers prompt
}


# ------
# no more sudo password

install_troubleshooting_packages_on_managed () {
    log_this "install troubleshooting RPM packages on $MANAGED_NODE_FQDN"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo dnf -y install \
            bash-completion \
            bind-utils \
            cockpit \
            lsof \
            nmap \
            nmap-ncat \
            plocate \
            vim \
            tcpdump \
            telnet \
            tmux \
            tree
}


setup_git_on_managed () {
    log_this "install and configure git on $MANAGED_NODE_FQDN"
    scp $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_HOME/.gitconfig $CONTROL_WORK_DIR/gitconfig-before-$MANAGED_NODE_FQDN
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN /usr/bin/bash $BASH_FLAG << EOF
        sudo dnf install --assumeyes git
        git config --global user.name         "$GIT_NAME"
        git config --global user.email        $GIT_EMAIL
        git config --global github.user       $GIT_USER
        git config --global push.default      simple
        # default timeout is 900 seconds (https://git-scm.com/docs/git-credential-cache)
        git config --global credential.helper 'cache --timeout=1200'
        git config --global pull.rebase false
        # check 
        git config --global --list
EOF
}


push_ca_certificate_to_managed () {
    # !!! copy CA certificate from installer host to all hypervisor host and VM trust stores. 
    #  * ca.source.example.com-cert.pem
    log_this "copy $CA_FQDN-cert.pem and $CA_FQDN-key.pem to $MANAGED_NODE_FQDN"
    scp ./$CA_FQDN-cert.pem $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_WORK_DIR/$CA_FQDN-cert.pem
    scp ./$CA_FQDN-key.pem  $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_WORK_DIR/$CA_FQDN-key.pem
    #
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN  /usr/bin/bash << EOF
        sudo cp $MANAGED_WORK_DIR/$CA_FQDN-cert.pem /etc/pki/ca-trust/source/anchors/
        sudo cp $MANAGED_WORK_DIR/$CA_FQDN-key.pem /etc/pki/tls/private/
        sudo chmod 0700  /etc/pki/tls/private/$CA_FQDN-key.pem
        sudo update-ca-trust
EOF
}



# This is a complicated alternative to ssh -o StrictHostKeyChecking=no 
trust_managed_host_key_and_name () {
    log_this "copy host key from managed $MANAGED_NODE_FQDN to control $CONTROL_NODE_NAME $CONTROL_HOME/.ssh/known_hosts file"
    # get a copy for backup
    cp $CONTROL_HOME/.ssh/known_hosts $CONTROL_WORK_DIR/known_hosts-before-names
    # add line if not already there
    LINE=$(ssh-keyscan $VERBOSE_FLAG -t ssh-ed25519 $MANAGED_NODE_FQDN)
    [[ "$VERBOSE" -eq 0 ]] && echo $LINE
    grep -qxF "$LINE" $CONTROL_HOME/.ssh/known_hosts || echo "$LINE" | tee -a $CONTROL_HOME/.ssh/known_hosts
}

set_managed_hostname () {
    log_this "set host name on managed $MANAGED_NODE_IP to $MANAGED_NODE_FQDN"
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
    log_this "change prompt in managed $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_HOME/.bashrc"
    # get a copy for backup
    scp $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_HOME/.bashrc $CONTROL_WORK_DIR/bashrc-$MANAGED_NODE_FQDN
    # add line if not already there
    LINE="PS1='[\u@\H \W]\$ '"      # oldskool
    LINE="PROMPT_USERHOST='\u@\H'"  # newskool
    # for me
    log_this "change PS1 in managed $MANAGED_HOME/.bashrc"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN "grep -qxF \"$LINE\" $MANAGED_HOME/.bashrc || echo \"$LINE\" | tee -a $MANAGED_HOME/.bashrc"
    # for root
    log_this "change PS1 in managed $/root/.bashrc"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN "sudo grep -qxF \"$LINE\" /root/.bashrc  || echo \"$LINE\" | sudo tee -a /root/.bashrc"
}



# SSH - worse security
# add root keys so root can log in remotely
root_login_to_managed () {
    log_this "allow key-based login to root@$MANAGED_NODE_FQDN"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo cp /root/.ssh/authorized_keys $MANAGED_WORK_DIR/authorized_keys-root
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo cp $MANAGED_HOME/.ssh/authorized_keys /root/.ssh/authorized_keys
}


# SSH - better security
# Use key-based login only, disable password login
# For more information, run 'man sshd_config'
restrict_ssh_auth_on_managed () {
    log_this "restrict SSH authentication to key only on $MANAGED_NODE_FQDN"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN "sudo grep -qxF 'AuthenticationMethods publickey' /etc/ssh/sshd_config  || echo 'AuthenticationMethods publickey' | sudo tee -a /etc/ssh/sshd_config"
}

copy_scripts_to_managed () {
    log_this "copy libvirt_utils to $MANAGED_NODE_FQDN"
    scp -r libvirt-utils $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_WORK_DIR
}

update_packages_on_managed () {
    log_this "update RPM packages on $MANAGED_NODE_FQDN"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo dnf -y update
}


# Connect to Red Hat Subscription Management
# Connect to Red Hat Insights
# Activate the Remote Host Configuration daemon
# Enable console.redhat.com services: remote configuration, insights, remediations, compliance
register_managed_with_RH () {
    log_this "check if $MANAGED_NODE_FQDN is already registered with RHSM"
    ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo subscription-manager status
    RET_RHSM=$?
    if [ $RET_RHSM -eq 1 ]
    then
        log_this "Register $MANAGED_NODE_FQDN with Red Hat. Use Simple Content Access, no need to attach a subscription."
        ssh $MANAGED_USER_NAME@$MANAGED_NODE_FQDN  /usr/bin/bash << EOF
            sudo rhc disconnect
            sleep 5
            sudo rhc connect --username="$RHSM_USER" --password="$RHSM_PASSWORD"
EOF
    fi
}


log_this () {
    [[ "$QUIET" -eq 0 ]] && return
    echo -n $(date) $0
    echo "  $1"
}



#-------------------------
# main

# on managed node
# at first, we login from control using the IPv4 address
ping_ip
# ssh_to_ip
trust_managed_host_key_and_ip
push_rsa_pubkey
create_managed_working_directory
push_passwordless_sudo
# after some config, we can login using the FQDN
ping_fqdn
trust_managed_host_key_and_name
set_managed_hostname
change_managed_prompt
root_login_to_managed
restrict_ssh_auth_on_managed
# connection work from control node to managed node is done 
# except for the Ansible user.
cd $CONTROL_WORK_DIR || exit 1  
register_managed_with_RH
setup_git_on_managed
push_ca_certificate_to_managed
install_troubleshooting_packages_on_managed
copy_scripts_to_managed
update_packages_on_managed