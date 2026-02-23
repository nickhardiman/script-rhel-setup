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
CONFIG_FILE=./rhel-setup.cfg
source $CONFIG_FILE
#
#-------------------------
# functions
#
does_ansible_user_exist() {
     ansible_user_exists=false
     id $CONTROL_ANSIBLE_NAME
     res_id=$?
     if [ $res_id -eq 0 ]
     then
       ansible_user_exists=true
     fi
}


# Create the Ansible account (not using --system). 
setup_control_ansible_user_account() {
    log_this "add an Ansible user account"
    sudo useradd $CONTROL_ANSIBLE_NAME
}

setup_managed_ansible_user_account() {
    log_this "add an Ansible user account"
    ssh -t $MANAGED_USER_NAME@$MANAGED_NODE_FQDN sudo useradd $MANAGED_ANSIBLE_NAME
}


setup_control_ansible_user_keys() {
    log_this "Create a new keypair. Put keys in /home/$CONTROL_ANSIBLE_NAME/.ssh/ and keep copies in /home/nick/.ssh/"
    ssh-keygen -f ./ansible-key -C "$CONTROL_ANSIBLE_NAME@$CONTROL_NODE_NAME" -q -N ""
    mv ansible-key  ansible-key.priv
    # Copy the keys to $CONTROL_ANSIBLE_NAME's SSH config directory. 
    sudo mkdir                               /home/$CONTROL_ANSIBLE_NAME/.ssh
    sudo chmod 0700                          /home/$CONTROL_ANSIBLE_NAME/.ssh
    sudo cp ansible-key.priv                 /home/$CONTROL_ANSIBLE_NAME/.ssh/id_rsa
    sudo chmod 0600                          /home/$CONTROL_ANSIBLE_NAME/.ssh/id_rsa
    sudo cp ansible-key.pub                  /home/$CONTROL_ANSIBLE_NAME/.ssh/id_rsa.pub
    sudo cp $CONTROL_HOME/.ssh/known_hosts           /home/$CONTROL_ANSIBLE_NAME/.ssh/known_hosts
    sudo chmod 0600                          /home/$CONTROL_ANSIBLE_NAME/.ssh/known_hosts
    sudo chown -R $CONTROL_ANSIBLE_NAME:$CONTROL_ANSIBLE_NAME  /home/$CONTROL_ANSIBLE_NAME/.ssh
    # Keep a spare set of keys handy. 
    # This location is set in ansible.cfg like this. 
    #   private_key_file = /home/me/.ssh/ansible-key.priv
    # Copy the keys to your SSH config directory. 
    cp ansible-key.priv  ansible-key.pub  $CONTROL_HOME/.ssh/
    # Clean up.
    # rm ansible-key.priv  ansible-key.pub
}


# For a RHEL control node, 
# These RPMs add files to 
#   /usr/share/ansible/roles/rhel-system-roles.*/
#   /usr/lib/python3.9/site-packages/ansible/
# and elsewhere.
#
# !!! how about installing the CLI tool "awx"?
# reference
#   https://docs.ansible.com/automation-controller/latest/html/controllercli/index.html
# install
#   sudo dnf --enablerepo=ansible-automation-platform-2.4-for-rhel-9-x86_64-rpms  install automation-controller-cli
#
# !!! how about ansible-lint and other tools?
# reference
#   https://github.com/nickhardiman/articles-ansible/blob/main/modules/use-ansible-tools/pages/index.adoc
# install
#   dnf --enablerepo=ansible-automation-platform-2.4-for-rhel-9-x86_64-rpms install ansible-lint
#
install_ansible_on_control() {
    log_this "install Ansible"
    source /etc/os-release
    if [[ "$PRETTY_NAME" =~ 'Red Hat Enterprise Linux' ]]
    then
        sudo dnf install --assumeyes ansible-core rhel-system-roles
    elif [[ "$PRETTY_NAME" =~ 'Fedora' ]]
    then
        sudo dnf install --assumeyes ansible-core linux-system-roles
    fi
}


setup_git_on_control () {
    log_this "install and configure git on $CONTROL_NODE_NAME"
    cp $CONTROL_HOME/.gitconfig $CONTROL_WORK_DIR/gitconfig-before-$CONTROL_NODE_NAME
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
}


# I'm not using ansible-galaxy because I make frequent changes.
# Check out the directive in ansible.cfg in some playbooks.
# If the repo has already been cloned, git exits with this error message. 
#   fatal: destination path 'libvirt-host' already exists and is not an empty directory.
#
clone_my_ansible_collections() {
    log_this "get my libvirt, OS and app roles, all bundled into a couple collections"
    mkdir -p $CONTROL_HOME/ansible/collections/ansible_collections/nick/
    pushd    $CONTROL_HOME/ansible/collections/ansible_collections/nick/
    # !!! when finished, move to requirements.yml 
    #   - git+https://github.com/nickhardiman/ansible-collection-aap2-refarch
    # !!! hacked copy of ansible-collection-platform
    # ansible-collection-aap2-refarch is a temporary copy of ansible-collection-platform
    # git clone https://github.com/nickhardiman/ansible-collection-platform.git platform
    git clone https://github.com/nickhardiman/ansible-collection-aap2-refarch.git platform
    git clone https://github.com/nickhardiman/ansible-collection-app.git      app
    popd
}


clone_my_playbooks_to_control() {
     log_this "get my playbook"
     sudo dnf install --assumeyes git
     mkdir -p $CONTROL_HOME/ansible/playbooks/
     pushd    $CONTROL_HOME/ansible/playbooks/
     git clone https://github.com/nickhardiman/ansible-playbook-aap2-refarch.git aap-refarch
     # cd ansible-playbook-$LAB_BUILD_NET_SHORT_NAME/
     popd
}


dl_from_galaxy_to_control() {
    log_this "install collections and roles from Ansible Galaxy and from Ansible Automation Hub"
    # Ansible Galaxy - https://galaxy.ansible.com
    # Ansible Automation Hub - https://console.redhat.com/ansible/automation-hub
    # Installing from Ansible Automation Hub requires the env var 
    # ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN.
    # install Ansible libvirt collection to the central location.
    sudo ansible-galaxy collection install community.libvirt \
        --collections-path /usr/share/ansible/collections
    # check 
    ls /usr/share/ansible/collections/ansible_collections/community/
    # Install other collections to ~/.ansible/collections/
    # (https://github.com/nickhardiman/ansible-playbook-build/blob/main/ansible.cfg#L13)
    cd ~/ansible/playbooks/aap-refarch/
    ansible-galaxy collection install -r collections/requirements.yml 
    # Install roles. 
    ansible-galaxy role install -r roles/requirements.yml 
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
does_ansible_user_exist
if $ansible_user_exists 
then
    log_this "ansible user already exists"
else
    setup_control_ansible_user_account
    setup_control_ansible_user_keys
fi
setup_managed_ansible_user_account
push_ansible_pubkey_to_managed
push_ansible_passwordless_sudo
install_ansible_on_control
clone_my_ansible_collections
clone_my_playbooks_to_control
dl_from_galaxy_to_control
