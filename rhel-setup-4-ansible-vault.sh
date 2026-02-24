#!/usr/bin/bash -x
#-------------------------
# Description
#
# Encrypt some sensitive values for Ansible. 
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

create_vault_on_control () {
     # Create a new vault file.
     echo "$VAULT_PASSWORD" > $VAULT_PASSWORD_FILE
     echo <<EOF> $VAULT_FILE
# secrets, tokens, user names, passwords, keys
# Whatever data you don't want to leak, stick it in a vault.
# Find the code on Github here. 
#   https://github.com/nickhardiman/script-rhel-setup
#
EOF
     ansible-vault encrypt --vault-pass-file $VAULT_PASSWORD_FILE $VAULT_FILE
}



# Each private key is multiline and requires indenting before adding to YAML file.
set_more_vault_secrets () {
    #
     log_this "copy my RSA keys for the vault"
     USER_ADMIN_PUBLIC_KEY=$(<$CONTROL_HOME/.ssh/id_rsa.pub)
     USER_ADMIN_PRIVATE_KEY_INDENTED=$(cat $CONTROL_HOME/.ssh/id_rsa | sed 's/^/    /')
    #
     log_this "copy ansible user's RSA keys for the vault"
     USER_ANSIBLE_PUBLIC_KEY=$(<$CONTROL_HOME/.ssh/ansible-key.pub)
     USER_ANSIBLE_PRIVATE_KEY_INDENTED=$(cat $CONTROL_HOME/.ssh/ansible-key.priv | sed 's/^/    /')
    #
     log_this "copy the CA's private key for the vault"
     CA_PRIVATE_KEY_INDENTED=$(sudo cat /etc/pki/tls/private/$CA_FQDN-key.pem | sed 's/^/    /')
}


add_secrets_to_vault () {
    log_this "add secrets to $VAULT_FILE"
     ansible-vault decrypt --vault-pass-file $VAULT_PASSWORD_FILE $VAULT_FILE
     cat << EOF >>  $VAULT_FILE
# misc
work_dir: $CONTROL_WORK_DIR
#
# accounts
default_password:        "$DEFAULT_PASSWORD"
rhsm_user:               "$RHSM_USER"
rhsm_password:           "$RHSM_PASSWORD"
user_admin_name:         "$CONTROL_USER_NAME"
user_admin_password:     "$DEFAULT_PASSWORD"
user_admin_public_key:    $USER_ADMIN_PUBLIC_KEY
user_admin_private_key: |
$USER_ADMIN_PRIVATE_KEY_INDENTED
user_ansible_name:       "$MANAGED_ANSIBLE_NAME"
user_ansible_password:   "$DEFAULT_PASSWORD"
user_ansible_public_key:  $USER_ANSIBLE_PUBLIC_KEY
user_ansible_private_key: |
$USER_ANSIBLE_PRIVATE_KEY_INDENTED
user_root_password:      "$DEFAULT_PASSWORD"
#
# tokens
ansible_galaxy_server_automation_hub_token: $ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN
jwt_red_hat_api: $OFFLINE_TOKEN
#
# PKI
ca_fqdn: $CA_FQDN
ca_private_key: |
$CA_PRIVATE_KEY_INDENTED
#
# network
site_ip: "$MANAGED_NODE_IP"
#
# manifests
aap_manifest_uuid: "$AAP_MANIFEST_UUID"
satellite_manifest_uuid: "$SATELLITE_MANIFEST_UUID"

EOF
     # Encrypt the new file. 
     ansible-vault encrypt --vault-pass-file $VAULT_PASSWORD_FILE $VAULT_FILE
}





log_this () {
    echo
    echo -n $(date)
    echo "  $1"
}


#-------------------------
# main

cd $CONTROL_WORK_DIR || exit 1
create_vault_on_control
set_more_vault_secrets
add_secrets_to_vault
