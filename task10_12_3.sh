#!bin/bash

export dir="$(cd "$(dirname "$0")" && pwd)"
export MAC=52:54:00:`(date; cat /proc/interrupts) | md5sum | sed -r 's/^(.{6}).*$/\1/; s/([0-9a-f]{2})/\1:/g; s/:$//;'`

#Exporting variables from config
export $(grep -v '#' $dir/tmp/config)
envsubst < $dir/tmp/config > $dir/config
export $(grep -v '#' $dir/config)
#Creating directories

mkdir /var/lib/libvirt/vm1
mkdir /var/lib/libvirt/vm2
mkdir $dir/networks
mkdir -p $dir/config-drives/vm1-config
mkdir -p $dir/config-drives/vm2-config
mkdir -p $dir/docker/etc
mkdir -p ${NGINX_LOG_DIR}
mkdir $dir/docker/certs

#Generating ssh key
yes "y" | ssh-keygen -f $(echo $SSH_PUB_KEY | rev | cut -c5- | rev) -N ""
export key="$(cat $SSH_PUB_KEY | cut -d ' ' -f2)"

#Preparation of file before using
envsubst < $dir/tmp/vm1.xml > $dir/vm1.xml
envsubst < $dir/tmp/vm2.xml > $dir/vm2.xml
envsubst < $dir/tmp/meta-datavm1 > $dir/config-drives/vm1-config/meta-data
envsubst < $dir/tmp/meta-datavm2 > $dir/config-drives/vm2-config/meta-data
envsubst < $dir/tmp/external.xml > $dir/networks/external.xml
envsubst < $dir/tmp/internal.xml > $dir/networks/internal.xml
envsubst < $dir/tmp/management.xml > $dir/networks/management.xml
envsubst < $dir/tmp/user-datavm1 > $dir/config-drives/vm1-config/user-data
envsubst < $dir/tmp/user-datavm2 > $dir/config-drives/vm2-config/user-data
envsubst < $dir/tmp/nginx_site > $dir/docker/etc/nginx_site.conf

#Creating certs
cd $dir/docker/certs
openssl req -newkey rsa:2048 -nodes -keyout privateCA.key \
-subj /C=UA/O=Mirantis/CN=$VM1_NAME/emailAddress=. -out CA_csr.csr
openssl x509 -signkey privateCA.key -in CA_csr.csr \
-req -days 365 -out root.crt
openssl genrsa -out nginx.web.key 2048
openssl req -new -key nginx.web.key \
-subj /C=UA/O=Mirantis/CN=$VM1_NAME/emailAddress=.  -out nginx.web.csr
openssl x509 -req \
-extfile <(printf "subjectAltName=IP:${VM1_EXTERNAL_IP}, DNS:${VM1_NAME}") -days 365\
 -in nginx.web.csr -CA root.crt\
 -CAkey privateCA.key -CAcreateserial -out web.crt
cat $dir/docker/certs/web.crt $dir/docker/certs/root.crt > $dir/docker/certs/web.pem



#Downloading base image, creating HDD and ISO files for both VM
wget -O /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $VM_BASE_IMAGE
cp /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $VM1_HDD
cp /var/lib/libvirt/images/ubuntu-server-16.04.qcow2 $VM2_HDD
genisoimage -o $VM1_CONFIG_ISO -V cidata -r -J --quiet $dir/config-drives/vm1-config  $dir/docker
genisoimage -o $VM2_CONFIG_ISO -V cidata -r -J --quiet $dir/config-drives/vm2-config

#Defining and starting networks
for n in $dir/networks/*
do
virsh net-define $n
done
virsh net-start external
virsh net-start internal
virsh net-start management

#Defining and starting VM's
virsh define $dir/vm1.xml
virsh define $dir/vm2.xml
virsh start vm1
virsh start vm2

