# shutdown VM guests
# takes a couple minutes to shut down. 
# check with
# sudo watch virsh list --all

for GUEST in \
  satellite.site3.example.com \
    gateway.site3.example.com 
do 
  sudo virsh shutdown $GUEST
  sleep 1
done

# shutdown host
sleep 10
sudo systemctl poweroff
