#!/bin/bash
set -o nounset
set -o errexit

echo "Reduce size of default FS to allow for Fusion FS creation"
SIZE=$(weka fs -o availableTotal --no-header -R --name default | cut -d ' ' -f 1) && sudo weka fs update default --total-capacity $((SIZE - 21474836480))

echo "Destroy SMB on WEKA"
  sudo weka smb cluster destroy -f
  
echo "Creating directory under /home/weka/ for smb-w"
  sudo mkdir /mnt/weka/ec2-user && sudo chown ec2-user.ec2-user /mnt/weka/ec2-user
  sudo mkdir /mnt/weka/smb-w

echo "Creating a host file for xargs and coping file to rest or hosts"
  cd /mnt/weka/ec2-user && weka cluster host -b -o ips |grep -v IPS > hosts.txt

echo "Creating FS /mnt/fusion for SMB-W"
  sudo weka fs create fusion default 10GB
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} "sudo mkdir /mnt/fusion && sudo mount -t wekafs -o readcache -o acl fusion /mnt/fusion"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 df -h -t wekafs |grep -i fusion

echo "Downloading the Tuxera image for AWS install"
  cd /mnt/weka/ec2-user && wget https://www.tuxera.com/download/wekaio/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster.tgz

echo "Unpacking tar"
  cd /mnt/weka/ec2-user  && tar -xzvf tuxera-smb-3022.2.22-x86_64-weka6-user-cluster.tgz


echo "Creating SMB-W Directories"
  sudo mkdir -m 777 /mnt/weka/data
  sudo mkdir -p /mnt/fusion/shared
  sudo mkdir -p /mnt/fusion/shared/tcp_params
  sudo mkdir -p /mnt/fusion/shared/ca_params
  sudo mkdir -p /mnt/fusion/shared/config
  sudo mkdir -p /mnt/fusion/shared/logs

echo "creating the SMB-W log directory on each host"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo mkdir -p /var/lib/tsmb/log

echo "copying the SMB-W binary to each host"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo cp /mnt/weka/ec2-user/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster/smb/bin/tsmb-server /usr/sbin
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo cp /mnt/weka/ec2-user/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster/smb/tools/* /usr/bin/
  #sudo cp /mnt/weka/ec2-user/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster/smb/conf/tsmb.conf /mnt/fusion/shared/config/


echo "Retrieving tsmb.conf file from github"
  wget https://raw.githubusercontent.com/weka/SMB-W/main/tsmb.conf?token=GHSAT0AAAAAABRDXNRWJRJTUY6JQHL6RIHIYR56NJQ
  sudo mv tsmb.conf* /mnt/fusion/shared/config/tsmb.conf

echo "Installing necessary packages for Active / Active setup"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo yum install corosync pacemaker pcs krb5-workstation passwd corosynclib realmd libnss-sss libpam-sss sssd sssd-tools adcli samba-common-bin packagekit krb5-user -y

echo "Enabling Services and starting pcsd"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} "sudo systemctl enable corosync && sudo systemctl enable pacemaker && sudo systemctl enable pcsd && sudo systemctl start pcsd"

echo "Running checks"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo systemctl status pcsd |grep -i active
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo systemctl status pacemaker |grep -i loaded

echo "Setup 'anything' resource agent"
  cd /mnt/weka/ec2-user && wget https://raw.githubusercontent.com/ClusterLabs/resource-agents/main/heartbeat/anything
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} "sudo cp /mnt/weka/ec2-user/anything /usr/lib/ocf/resource.d/heartbeat/ && sudo chmod a+rwx /usr/lib/ocf/resource.d/heartbeat/anything"

echo "Checking that the heartbeat file is distributed across the cluster"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo pcs resource agents ocf:heartbeat | grep  anything

echo "HA Cluster Setup / You will be asked for a password.  Please use hacluster/weka.io123"
  for i in `cat /mnt/weka/ec2-user/hosts.txt`; do ssh $i "echo weka.io123 | sudo passwd hacluster --stdin";done

echo "Authorizing Nodes"
  sudo pcs cluster auth `weka cluster host -b -o hostname --no-header | tr '\n' ' '`

echo "Setting up the cluster"
  sudo pcs cluster setup --name tuxha `weka cluster host -b -o hostname --no-header | tr '\n' ' '` --force

echo "Starting the cluster"
  sudo pcs cluster start --all

echo "Enabling the cluster"
  sudo pcs cluster enable --all

echo "Configuration Options"
  sudo pcs property set stonith-enabled=false
  sudo pcs property set no-quorum-policy=ignore
  
echo "Setup adcli join"
  sudo adcli join --domain WEKADEMO.COM --service-name=cifs --computer-name SMB-W --host-fqdn smb-w.WEKADEMO.COM -v -U Administrator -P Weka.io123456
  
echo "Retrieving sssd.conf and propogating"
  wget https://raw.githubusercontent.com/weka/SMB-W/main/sssd.conf?token=GHSAT0AAAAAABRDXNRW6JPB2ZOGHAU5STD2YR6BMQA
  sudo cp sssd* /mnt/fusion/sssd.conf
  sudo cp /etc/krb5.keytab /mnt/fusion/krb5.keytab
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} "sudo cp /mnt/fusion/krb5.keytab /etc/ && sudo cp /mnt/fusion/sssd.conf /etc/sssd/ && sudo chmod 600 /etc/sssd/sssd.conf" 

echo "start the sssd service"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo systemctl start sssd

echo "Creating the tsmb_ha cluster resource"
  sudo pcs resource create tsmb_ha ocf:heartbeat:anything binfile=/usr/sbin/tsmb-server cmdline_options="-c /mnt/fusion/shared/config/tsmb.conf -p"

echo "Cloning the cluster resource to the rest of the nodes"
  sudo pcs resource clone tsmb_ha clone-max=6
  sudo pcs cluster stop --all;sleep 20 && sudo pcs cluster start --all

echo "Post Installation checks"
  sudo pcs status
  sudo pcs cluster status
  tail -20 /var/lib/tsmb/log/tsmb.log
