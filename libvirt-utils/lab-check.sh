# check VMs
# requires root .ssh work: ssh-keygen, ssh-copy-id, known_hosts

for GUEST in \
    gateway.site1.example.com \
  satellite.site1.example.com 
do 
  echo -n "$GUEST: "
  ssh nick@$GUEST echo 'alive'
  sleep 1
done