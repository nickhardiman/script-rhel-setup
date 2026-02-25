# This bash script creates a new KVM virtual machine on RHEL with libvirt.
# It takes a "KVM Guest Image" and customizes it.
# Then it creates a new VM and customizes that too.

# copy the one of the "Virtualization Images"  from
# https://access.redhat.com/downloads/content/rhel
# to here.
# I'm using "Red Hat Enterprise Linux 8.2 KVM Guest Image", 
# with the file name "rhel-8.2-x86_64-kvm.qcow2".
POOL=images
POOL_DIR=/var/lib/libvirt/libvirt/$POOL


# customize the KVM Guest Image
HOST=my-new-host
IMAGE=$HOST.qcow2
VIRT_RESIZE_OPTIONS="--expand /dev/sda3 rhel-8.2-x86_64-kvm.qcow2 $IMAGE"
CPUS=2
MEMORY=4092
DISK_SIZE=20G
OS_VARIANT=rhel8.2
# first network interface
IF1_MAC=52:54:00:00:00:03
IF1_IP=192.168.122.3
IF1_DOMAIN=lab.example.com
IF1_BRIDGE=virbr0
# second network interface
IF2_MAC=52:54:00:00:01:03
IF2_IP=192.168.152.3
IF2_DOMAIN=private.example.com
IF2_BRIDGE=virbr1

# make a bigger copy of the downloaded image
cd $POOL_DIR
echo virsh vol-create-as $POOL $IMAGE $DISK_SIZE
virsh vol-create-as $POOL $IMAGE $DISK_SIZE
echo virt-resize $VIRT_RESIZE_OPTIONS 
virt-resize $VIRT_RESIZE_OPTIONS

# cloud-init package installed in rhel7 image, but not 8
# harmless for rhel8 
virt-customize \
  --add            $POOL_DIR/$IMAGE \
  --root-password  password:'Password;1' \
  --hostname       $HOST.$IF1_DOMAIN \
  --timezone       'Europe/London' \
  --uninstall      cloud-init  \
  --uninstall      initial-setup  \
  --ssh-inject     'root:string:ssh-rsa ABCDB3NzaC1yc2EAAAADAQABAAABgQDS9WOAwF/q1dKoHt+CqI1HTmEUNseC/fn3eiDBK/fd3MufeXSBuZzh/jSvM1fV5sCygGm+eblteu6EyCW9ozllsv4tB5SgPzDiiz3DqP4hHqpQ6Vr/2UAPx+549RZ/n/hij6DB15s/IzXvzId4yZTOchsmKUASFsHgfFEXGl77RfH1eEUxcTQ+mte5Uv7DXFt7gk5t9aB40yRGIwYACxesZvjrdcxPiWSvjFt345mYkbYlmsdHEr/zNVhrgV4msD7TedFzDg6NZ85Fze+C2lqKLd/O9BBpVkKkiALQaIHqMotysldAr+IjCj9xC8yqiFfb3ll+ra089JWeIbj83qcUHDUGHdxr8u4J6/zURlJSaGnlt2mVo6kN8KAYTR92B2d0VYBjTngzeo7Rciqw5pZXWm1pwFSBxhaYzeEoHshCxa0PN+D0H1IzVPveqK/pPNoF7AVBhccRoCOx24pU7DGC/gJo6RM52yDgofnr2i2oSjB8ZsJ0WFb2Gq36mrefgh= root@rpi4.lab.example.com'  \
  --selinux-relabel
  

# create a new VM
# one network interface
if [ -z $IF2_IP ] ; then 
  virt-install   \
    --network    bridge:${IF1_BRIDGE},mac=$IF1_MAC   \
    --name       $HOST   \
    --memory     $MEMORY \
    --vcpus      $CPUS \
    --disk       $POOL_DIR/$IMAGE  \
    --os-variant $OS_VARIANT \
    --import   \
    --graphics   none   \
    --noautoconsole
else 
# two network interfaces
  virt-install   \
    --network    bridge:${IF1_BRIDGE},mac=$IF1_MAC   \
    --network    bridge:${IF2_BRIDGE},mac=$IF2_MAC   \
    --name       $HOST   \
    --memory     $MEMORY \
    --vcpus      $CPUS \
    --disk       $POOL_DIR/$IMAGE  \
    --os-variant $OS_VARIANT \
    --import   \
    --graphics   none   \
    --noautoconsole
fi


# customize the hypevisor
# add host DNS
# echo "$IF1_IP   $HOST" >> /etc/hosts


# customize the VM
# add key login 
ssh-copy-id $HOST

exit

# This doesn't run because of the "exit" commmand.
# more customization for the new machine 

# add user accounts
for NAME in nick ansible_user
do
  useradd $NAME
  usermod -a -G wheel $NAME
  echo 'Password;1' | passwd --stdin $NAME
done 

# network config required?
CON_NAME='Wired connection 1'
IF2_IP=192.168.152.3
nmcli connection modify "$CON_NAME" ipv4.addresses $IF2_IP/24
nmcli connection modify "$CON_NAME" ipv4.method    manual
nmcli connection up "$CON_NAME" 
