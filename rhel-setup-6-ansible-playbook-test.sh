#!/usr/bin/bash -x
#-------------------------
# Description
#
# Create a simple playbook to test. 
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
TEST_DIR=$CONTROL_HOME/ansible/playbooks/test

#-------------------------
# functions
#


create_playbook_dirs() {
     log_this "create playbook directories"
     mkdir -p $TEST_DIR
}


create_config_file () {
    log_this "create config"
     cat << EOF >  $TEST_DIR/ansible.cfg
# https://docs.ansible.com/ansible/latest/reference_appendices/config.html
[defaults]
inventory=inventory.ini
remote_user = $MANAGED_ANSIBLE_NAME
private_key_file = $CONTROL_HOME/.ssh/ansible-key.priv
# disable known_hosts check
host_key_checking = False
collections_paths = ~/ansible/collections:~/.ansible/collections:/usr/share/ansible/collections
nocows=1
# https://docs.ansible.com/ansible/2.9/plugins/callback/profile_tasks.html
callback_whitelist = profile_tasks

EOF
}


create_inventory_file () {
    log_this "create inventory"
    cat << EOF >  $TEST_DIR/inventory.ini
[managed_node]
$MANAGED_NODE_FQDN
EOF
}


create_playbook () {
    log_this "create playbook"
    cat << EOF >  $TEST_DIR/playbook.yml
---
- name: Simple ping
  hosts: all
  tasks:
    - name: Message before 
      ansible.builtin.debug:
        msg: Connect to host {{ inventory_hostname }} as remote_user {{ user_ansible_name }}
    - name: SSH to the managed host 
      ansible.builtin.ping:

EOF
}


run_playbook () {
    log_this "run playbook"
    cd $TEST_DIR
    ansible-playbook \
      --extra-vars=@$VAULT_FILE \
      --vault-pass-file=$VAULT_PASSWORD_FILE  \
      playbook.yml
}


log_this () {
    echo
    echo -n $(date)
    echo "  $1"
}


#-------------------------
# main

create_playbook_dirs
create_config_file
create_inventory_file
create_playbook
run_playbook
