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

passwordless_sudo () {
    log_this "configure sudo for passwordless privilege escalation here ($CONTROL_USER_NAME@$CONTROL_NODE_NAME)"
    echo "$CONTROL_USER_NAME      ALL=(ALL)       NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$CONTROL_USER_NAME
}

# Connect to Red Hat Subscription Management
# Connect to Red Hat Insights
# Activate the Remote Host Configuration daemon
# Enable console.redhat.com services: remote configuration, insights, remediations, compliance
register_control_with_RH () {
    log_this "check if $CONTROL_NODE_FQDN is already registered with RHSM"
    sudo subscription-manager status
    RET_RHSM=$?
    if [ $RET_RHSM -eq 1 ]
    then
        log_this "Register $CONTROL_NODE_FQDN with Red Hat. Use Simple Content Access, no need to attach a subscription."
        sudo rhc disconnect
        sleep 5
        sudo rhc connect --username="$RHSM_USER" --password="$RHSM_PASSWORD"
    fi
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
change_control_prompt () {
    log_this "change PS1 in control $CONTROL_HOME/.bashrc"
    # get a copy for backup
    cp $CONTROL_HOME/.bashrc $CONTROL_WORK_DIR/bashrc-$CONTROL_NODE_FQDN
    # add line if not already there
    LINE="PS1='[\u@\H \W]\$ '"      # oldskool
    LINE="PROMPT_USERHOST='\u@\H'"  # newskool
    # for me
    grep -qxF $LINE $CONTROL_HOME/.bashrc || echo $LINE | tee -a $CONTROL_HOME/.bashrc
    # for root
    sudo grep -qxF $LINE /root/.bashrc  || echo $LINE | sudo tee -a /root/.bashrc
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

update_control_hosts_file () {
    log_this "add managed $MANAGED_NODE_IP to control $CONTROL_NODE_NAME /etc/hosts file"
    # get a copy for backup
    # scp $MANAGED_USER_NAME@$MANAGED_NODE_IP:/etc/hosts $CONTROL_WORK_DIR/hosts-$MANAGED_NODE_IP
    # add lines if not already there
    LINE="$MANAGED_NODE_IP  $MANAGED_NODE_FQDN"
    grep -qxF "$LINE" /etc/hosts || echo "$LINE" | sudo tee -a /etc/hosts
}

# Role https://github.com/nickhardiman/ansible-collection-platform/tree/main/roles/server_cert
# expects to find a CA certificate and matching private key.
# CA private key, a file on the hypervisor here.
#   /etc/pki/tls/private/$CA_FQDN-key.pem
# CA certificate, a file on the hypervisor here.
#   /etc/pki/ca-trust/source/anchors/$CA_FQDN-cert.pem
# https://hardiman.consulting/rhel/9/security/id-certificate-ca-certificate.html
setup_ca_certificate_on_control () {
    log_this "create a CA certificate on control $CONTROL_NODE_NAME"
    if [ -f  "./$CA_FQDN-key.pem" ]; then
        log_this "skipping, found this CA key file: $CA_FQDN-key.pem"
        return 1
    fi
    # Create a CA private key.
    openssl genrsa \
        -out $CA_FQDN-key.pem 2048
    # Create a CA certificate.
    openssl req \
        -x509 \
        -sha256 \
        -days 365 \
        -nodes \
        -key ./$CA_FQDN-key.pem \
        -subj "/C=UK/ST=mystate/O=myorg/OU=myou/CN=$CA_FQDN" \
        -out $CA_FQDN-cert.pem
    # https://hardiman.consulting/rhel/9/security/id-certificate-ca-trust.html
    # Trust the certificate on installer. 
    sudo cp ./$CA_FQDN-cert.pem /etc/pki/ca-trust/source/anchors/
    sudo cp  ./$CA_FQDN-key.pem /etc/pki/tls/private/
    sudo update-ca-trust
}


update_packages_on_control () {
    log_this "update RPM packages on $CONTROL_NODE_NAME"
    sudo dnf -y update
}


log_this () {
    echo
    echo -n $(date)
    echo "  $1"
}

#-------------------------
# main

# on control node

change_control_prompt
passwordless_sudo
register_control_with_RH
create_control_working_directory
create_control_rsa_keys  
update_control_hosts_file
setup_ca_certificate_on_control
update_packages_on_control