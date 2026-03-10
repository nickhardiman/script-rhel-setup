# Tell a MacOS workstation how to get to VMs.
# to get to the lab network, go via the hypervisor.
# eg. A route is needed to make this command work.
#   me@workstation:#  ssh ansible_user@192.168.134.5
#
# Network is defined in 
# https://github.com/nickhardiman/ansible-collection-libvirt/blob/main/roles/libvirt_net_private/defaults/main.yml
# MacOS is BSD, not Linux, and uses the "route add" command.
# The RHEL version would be something like 
#   ip route add $LAB_NET via $HYPERVISOR
# or
#   nmcli connection modify enp1s0 +ipv4.routes "$LAB_NET $HYPERVISOR"
# Virtualbox NAT uses the host network, so this can also fix guest routing.
# To back out the change, replace "add" with "delete".
#   route delete -net  $LAB_NET $HYPERVISOR
#
LAB_NET="192.168.134.0/24"
HYPERVISOR=192.168.1.253
sudo route add -net $LAB_NET $HYPERVISOR
#
# check the routing table
# list IPv4 routes 
netstat -nr -f inet
