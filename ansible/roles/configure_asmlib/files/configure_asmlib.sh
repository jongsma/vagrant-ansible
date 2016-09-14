#!/bin/bash

# configure ASMLib
sudo /etc/init.d/oracleasm configure <<EOF
oracle
dba
y
y
EOF

# stamp disks
# i=1 
# for dev in `ls /dev/sd*1 | grep -v a`; do sudo /etc/init.d/oracleasm createdisk ASMDISK$((i++)) $dev; done
