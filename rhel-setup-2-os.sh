#!/usr/bin/bash -x
#-------------------------
# Description
#
# Customize RHEL on the managed node
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

# Enable nested virtualization? 
# In /etc/modprobe.d/kvm.conf 
# options kvm_amd nested=1


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
        ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN << EOF 
            sudo rhc disconnect
            sleep 5
            sudo rhc connect --username="$RHSM_USER" --password="$RHSM_PASSWORD"
EOF
    fi
}


install_troubleshooting_packages_on_managed () {
    log_this "install troubleshooting RPM packages on $MANAGED_NODE_FQDN"
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo dnf -y install \
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
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN << EOF 
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


setup_ca_certificate_on_control () {
    log_this "create a CA certificate on control $CONTROL_NODE_NAME"
    # Role https://github.com/nickhardiman/ansible-collection-platform/tree/main/roles/server_cert
    # expects to find a CA certificate and matching private key.
    # CA private key, a file on the hypervisor here.
    #   /etc/pki/tls/private/$CA_FQDN-key.pem
    # CA certificate, a file on the hypervisor here.
    #   /etc/pki/ca-trust/source/anchors/$CA_FQDN-cert.pem
    # https://hardiman.consulting/rhel/9/security/id-certificate-ca-certificate.html
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


push_ca_certificate_to_managed () {
    # !!! copy CA certificate from installer host to all hypervisor host and VM trust stores. 
    #  * ca.source.example.com-cert.pem
    for NAME in host.site1.example.com host.site2.example.com host.site3.example.com
    do
        scp ./$CA_FQDN-cert.pem $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_WORK_DIR/$CA_FQDN-cert.pem
        scp ./$CA_FQDN-key.pem  $MANAGED_USER_NAME@$MANAGED_NODE_FQDN:$MANAGED_WORK_DIR/$CA_FQDN-key.pem
        ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN  << EOF 
            sudo cp $MANAGED_WORK_DIR/$CA_FQDN-cert.pem /etc/pki/ca-trust/source/anchors/
            sudo cp $MANAGED_WORK_DIR/$CA_FQDN-key.pem /etc/pki/tls/private/
            sudo chmod 0700  /etc/pki/tls/private/$CA_FQDN-key.pem
            sudo update-ca-trust
EOF
    done
}


update_packages_on_managed () {
    log_this "update RPM packages on $MANAGED_NODE_FQDN"
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo dnf -y update
}


log_this () {
    echo
    echo -n $(date)
    echo "  $1"
}



#-------------------------
# main

# connection work from control node to managed node is done 
# except for the Ansible user.
cd $CONTROL_WORK_DIR || exit 1  
register_managed_with_RH
setup_git_on_managed
setup_ca_certificate_on_control
push_ca_certificate_to_managed
install_troubleshooting_packages_on_managed
update_packages_on_managed