# start VMs
# check with
# virsh list --all
for GUEST in \
    gateway.site1.example.com \
  satellite.site1.example.com 
do 
  echo virsh start $GUEST
  sudo virsh start $GUEST
  sleep 1
done

virsh list --all
