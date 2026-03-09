# Tell a MacOS workstation how to get to VMs.
# eg.
#   ssh ansible_user@192.168.134.5
# Network is defined in 
# https://github.com/nickhardiman/ansible-collection-libvirt/blob/main/roles/libvirt_net_private/defaults/main.yml
#
# to get to the lab network, go via the hypervisor.
LAB_NET="192.168.134.0/24"
HYPERVISOR=192.168.1.253
sudo route add -net $LAB_NET $HYPERVISOR
#
# check the routing table
# list IPv4 routes 
netstat -nr -f inet
