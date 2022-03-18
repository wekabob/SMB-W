#!/bin/bash
set -o nounset
set -o errexit

echo "Reduce size of default FS to allow for Fusion FS creation"
SIZE=$(weka fs -o availableTotal --no-header -R --name default | cut -d ' ' -f 1) && sudo weka fs update default --total-capacity $((SIZE - 21474836480))

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
  sudo mkdir /mnt/fusion/shared
  sudo mkdir /mnt/fusion/shared/tcp_params
  sudo mkdir /mnt/fusion/shared/ca_params
  sudo mkdir /mnt/fusion/shared/config
  sudo mkdir /mnt/fusion/shared/logs

echo "creating the SMB-W log directory on each host"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo mkdir -p /var/lib/tsmb/log

echo "copying the SMB-W binary to each host"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo cp /mnt/weka/ec2-user/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster/smb/bin/tsmb-server /usr/sbin
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo cp /mnt/weka/ec2-user/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster/smb/tools/* /usr/bin/
  #sudo cp /mnt/weka/ec2-user/tuxera-smb-3022.2.22-x86_64-weka6-user-cluster/smb/conf/tsmb.conf /mnt/fusion/shared/config/


echo "Creating tsmb conf file"
cat << HERE > /mnt/fusion/shared/config/tsmb.conf
[global]
#change to text when working with local users - no AD integration
    userdb_type = ad
# uncomment the line below if you want to use local users
#    userdb_file = /mnt/fusion/shared/config/users_db.txt
    runstate_dir = /var/lib/tsmb
    enable_ipc = true
    domain = WEKADEMO.COM

#Set the interface used for Fusion resources (e.g enp59s0f1)
    listen = ANY,0.0.0.0,IPv4,445,DIRECT_TCP
    listen = ANY,::,IPv6,445,DIRECT_TCP
    listen = ANY,0.0.0.0,IPv4,139,NBSS
# For RDMA replace previous line with
#   listen = ANY,0.0.0.0,RDMA_IPv4,445,SMBD
    dialects = SMB2.002 SMB2.1 SMB3.0 SMB3.02 SMB3.1.1
# set to true if you want to allow guest access
    allow_guest = false
    null_session_access = false
    require_message_signing = false
    encrypt_data = false
    reject_unencrypted_access = true
    unix_extensions = true
    enable_oplock = true
    # Using log_destination = syslog or file if you want to use dedicated log file
    log_destination = file
    log_level = 4
    log_params = path=/var/lib/tsmb/tsmb.log,timestamp=true
    durable_v1_timeout = 960
    durable_v2_timeout = 180
  sess_open_files_max = 1048574
  open_files_max = 1048576
  connections_max = 1048576
  vfs_metadata_threads = 1024
  vfs_data_threads = 1024
  transport_rx_threads = 256
  transport_tx_threads = 256
  tcp_tickle = true
  tcp_tickle_params = path=/mnt/fusion/shared/tcp_params
  # Only users with uidnumber/gidnumber will be able to access shares
  authz_require_posix = true
  ca = true
  ca_path = /mnt/fusion/shared/ca_params
#Server name is the value you set for joining windows AD and should be added to the DNS as well
  server_name = smb-w
# For MMC support
  privilegedb = /mnt/fusion/shared/config/privilege
# Enable Auditing - Need also to enable per share
  audit_enable = true
  audit_params = path=/mnt/fusion/shared/logs/Audit,days=1,uid=true,sensitive_data=allow
[/global]
[share]
  netname = C$
  remark = Sample administrative share
  path = /mnt/weka_acl
  administrative = true
[/share]
[share]
  netname = public
  remark = Exporting /mnt/weka/data
  path = /mnt/weka_acl/smb
  permissions = everyone:full
# ca = true
# ca_params = path=/mnt/fusion/shared/ca_params
#This for snapshot integration , make sure you .snapshots directory exist , share_root should point to relative path of the directory you share
  vss = true
  vss_params = path=/mnt/weka_acl/.snapshots,share_root=data,vg_name=smb_test_vg,fs_type=ext4
# Enable Audit
  audit_level = 5
#By default SMB-W is case sensitive
 case_insensitive = true
[/share]
HERE

echo "Installing necessary packages for Active / Active setup"
  cat /mnt/weka/ec2-user/hosts.txt |xargs -I {} -P 0 ssh {} sudo yum install corosync pacemaker pcs krb5-workstation passwd corosynclib realmd libnss-sss libpam-sss sssd sssd-tools adcli
samba-common-bin packagekit krb5-user -y

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

echo "Creating the tsmb_ha cluster resource"
  sudo pcs resource create tsmb_ha ocf:heartbeat:anything binfile=/usr/sbin/tsmb-server cmdline_options="-c /mnt/fusion/shared/config/tsmb.conf -p"

echo "Cloning the cluster resource to the rest of the nodes"
  sudo pcs resource clone tsmb_ha clone-max=6
  sudo pcs cluster stop --all;sleep 20 && sudo pcs cluster start --all

echo "Post Installation checks"
  sudo pcs status
  sudo pcs cluster status
  tail -20 /var/lib/tsmb/log/tsmb.log