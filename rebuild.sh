#!/bin/bash
# set -x

GETMOS="./getMOSPatch.jar"
MOS_USERNAME="kjongsma@vxcompany.com"
MOS_PASSWORD=
GI_FILE_1="p21419221_121020_Linux-x86-64_5of10.zip"
GI_FILE_1MD5="b8abeffd6c0837716e8b1706d5cebad8"
GI_FILE_2="p21419221_121020_Linux-x86-64_6of10.zip"
GI_FILE_2MD5="52395e136529510438165272978835fc"
DB_FILE_1="p21419221_121020_Linux-x86-64_1of10.zip"
DB_FILE_1MD5="72d841081be9ad6e3468c2a0191059b1"
DB_FILE_2="p21419221_121020_Linux-x86-64_2of10.zip"
DB_FILE_2MD5="7f93edea2178e425ff46fc8e52369ea3"

command -v wget >/dev/null 2>&1 || 
	{ echo >&2 "wget not found or installed, exiting..."; exit 1; }
command -v vagrant >/dev/null 2>&1 || 
	{ echo >&2 "vagrant not found or installed, exiting..."; exit 1; }
command -v ansible >/dev/null 2>&1 || 
	{ echo >&2 "ansible not found or installed, exiting..."; exit 1; }
command -v java >/dev/null 2>&1 || 
	{ echo >&2 "java not found or installed, exiting..."; exit 1; }
command -v VBoxManage >/dev/null 2>&1 || 
	{ echo >&2 "VirtualBox not found or installed, exiting..."; exit 1; }

# Get getMOSPatch.jar
	FILE="/Users/klaasjan/vagrant/rac/getMOSPatch.jar"
 
	if [ -f "$GETMOS" ];
	then
	   echo "File $GETMOS exist, continuing..."
	else
	   echo "File $GETMOS does not exist"
	   wget https://github.com/MarisElsins/getMOSPatch/raw/master/getMOSPatch.jar
	fi

# Prepare GI zipfiles 
	if [ -f "./ansible/roles/rac_install_gi/files/$GI_FILE_1" ];
	then
	   echo "File $GI_FILE_1 exist, continuing..."
	else
	   echo "File $GI_FILE_1 does not exist, downloading"
	   java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*5of10.* download=all
	   mv $GI_FILE_1 ./ansible/roles/rac_install_gi/files/
	fi

	if [ -f "./ansible/roles/rac_install_gi/files/$GI_FILE_2" ];
	then
	   echo "File $GI_FILE_2 exist, continuing..."
	else
	   echo "File $GI_FILE_2 does not exist, downloading"
	   java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*6of10.* download=all
	   mv $GI_FILE_2 ./ansible/roles/rac_install_gi/files/
	fi

	if [ `md5 -q ansible/roles/rac_install_gi/files/$GI_FILE_1` == "$GI_FILE_1MD5" ]; 
		then echo "MD5 for $GI_FILE_1 is OK"
	else 
		rm ansible/roles/rac_install_gi/files/$GI_FILE_1
		java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*6of10.* download=all
		mv $GI_FILE_1 ./ansible/roles/rac_install_gi/files/
	fi

	if [ `md5 -q ansible/roles/rac_install_gi/files/$GI_FILE_2` == "$GI_FILE_2MD5" ]; 
		then echo "MD5 for $GI_FILE_2 is OK"
	else 
		rm ansible/roles/rac_install_gi/files/$GI_FILE_2
		java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*6of10.* download=all
		mv $GI_FILE_2 ./ansible/roles/rac_install_gi/files/
	fi

# Prepare DB zipfiles 
	if [ -f "./ansible/roles/rac_install_db/files/$DB_FILE_1" ];
	then
	   echo "File $DB_FILE_1 exist, continuing..."
	else
	   echo "File $DB_FILE_1 does not exist, downloading"
	   java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*1of10.* download=all
	   mv $DB_FILE_1 ./ansible/roles/rac_install_db/files/
	fi

	if [ -f "./ansible/roles/rac_install_db/files/$DB_FILE_2" ];
	then
	   echo "File $DB_FILE_2 exist, continuing..."
	else
	   echo "File $DB_FILE_2 does not exist, downloading"
	   java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*2of10.* download=all
	   mv $DB_FILE_2 ./ansible/roles/rac_install_db/files/
	fi

	if [ `md5 -q ansible/roles/rac_install_db/files/$DB_FILE_1` == "$DB_FILE_1MD5" ]; 
		then echo "MD5 for $DB_FILE_1 is OK"
	else 
		rm ansible/roles/rac_install_db/files/$DB_FILE_1
		java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*1of10.* download=all
		mv $DB_FILE_1 ./ansible/roles/rac_install_db/files/
	fi

	if [ `md5 -q ansible/roles/rac_install_db/files/$DB_FILE_2` == "$DB_FILE_2MD5" ]; 
		then echo "MD5 for $DB_FILE_2 is OK"
	else 
		rm ansible/roles/rac_install_db/files/$DB_FILE_2
		java -jar getMOSPatch.jar MOSUser="$MOS_USERNAME" MOSPass="$MOS_PASSWORD" patch=21419221 platform=226P regexp=.*2of10.* download=all
		mv $DB_FILE_2 ./ansible/roles/rac_install_db/files/
	fi

# Recreate vboxnet0 with correct settings
# VBoxManage hostonlyif remove vboxnet0
# VBoxManage hostonlyif create
# VBoxManage hostonlyif ipconfig vboxnet0 --ip 192.168.78.1 --netmask 255.255.255.0

# rebuild RAC
# clear
# vagrant destroy -f
# vagrant up

set +x