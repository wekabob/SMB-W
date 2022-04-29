# SMB-W
Script which will later be used by Ansible for Deploying SMB-W in AWS

Steps for Deployment

1.  Spin up AWS instance with Jenkins http://172.29.0.241:8080/ with SETUP_SMB selected.
2.  SSH to one of the backend nodes and pull this repo to /home/ec2-user 

[ec2-user@ip-172-31-73-211 ~]$ git clone https://github.com/weka/SMB-W
Cloning into 'SMB-W'...
remote: Enumerating objects: 69, done.
remote: Counting objects: 100% (69/69), done.
remote: Compressing objects: 100% (68/68), done.
remote: Total 69 (delta 37), reused 0 (delta 0), pack-reused 0
Receiving objects: 100% (69/69), 22.59 KiB | 5.65 MiB/s, done.
Resolving deltas: 100% (37/37), done.
[ec2-user@ip-172-31-73-211 ~]$ ls -ltr
total 0
drwxrwxr-x 3 ec2-user ec2-user 109 Apr 29 14:45 SMB-W
[ec2-user@ip-172-31-73-211 ~]$ cd SMB-W/
[ec2-user@ip-172-31-73-211 SMB-W]$ ls -ltr
total 32
-rw-rw-r-- 1 ec2-user ec2-user  2568 Apr 29 14:45 tsmb.conf
-rw-rw-r-- 1 ec2-user ec2-user   503 Apr 29 14:45 sssd.conf
-rw-rw-r-- 1 ec2-user ec2-user  5526 Apr 29 14:45 SMB-W-Install.sh
-rw-rw-r-- 1 ec2-user ec2-user    78 Apr 29 14:45 README.md
-rw-rw-r-- 1 ec2-user ec2-user 10829 Apr 29 14:45 anything
[ec2-user@ip-172-31-73-211 SMB-W]$

3.  Run the SMB-W-Install.sh script

4.  RDP to the AD Server
7.  
