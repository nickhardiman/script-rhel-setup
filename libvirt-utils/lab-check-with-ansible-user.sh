# check VMs from control node
# All keys are distributed by the build process.
# See https://github.com/nickhardiman/ansible-collection-aap2-refarch/blob/main/roles/libvirt_machine_kickstart/templates/kvm-guest-nic-static.ks.j2
 

echo site3
for GUEST in \
    gateway-site3.home \
  satellite.site3.example.com
do
  echo -n "$GUEST: "
  ssh -i ~/.ssh/ansible-key.priv ansible_user@$GUEST echo 'alive'
  sleep 1
done
