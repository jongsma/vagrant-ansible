# -*- mode: ruby -*-
# vi: set ft=ruby :

vagrant_api   = "2"              # Version of vagrant API, should be 2
ASM_LOC       = "./asmdisk"      # Physical location of disks relevant to Vagrantfile
num_disks     = 4                # Number of ASM disks
host_prefix   = "rac"            # Hostname prefix
servers       = 2                # Amount of RAC nodes
mem           = 4096             # Memory per node in MB
cpu           = 2                # CPU count per node
devmanager    = "udev"           # Devive Manager [udev|asmlib]
db_create_cdb = "true"           # Create CDB [true|false]
db_pdb_amount = 1                # Amount of PDB's to create
db_name       = "mycdb"          # Name of (C)DB
db_total_mem  = 800              # Total amount of PGA + SGA in MB
domain_name   = "mydomain.local" # Domain name of the RAC cluster

Vagrant.configure(vagrant_api) do |config|
config.vm.box = "jongsma/oel68"
config.ssh.forward_x11   = true
config.ssh.forward_agent = true

	(1..servers).each do |rac_id|
	config.vm.define "#{host_prefix}#{rac_id}" do |config|
	config.vm.hostname = "#{host_prefix}#{rac_id}"

	# Do Virtualbox configuration 
	config.vm.provider :virtualbox do |vb|
		vb.customize ['modifyvm', :id, '--nic2', 'intnet', '--intnet2', 'rac-priv']
		vb.customize ['modifyvm', :id, '--nic3', 'hostonly', '--hostonlyadapter3', 'vboxnet0']
		# Give NIC a fixed MAC address so we can use udev for device path persistency 
		vb.customize ['modifyvm', :id, '--macaddress2', "080027AAAA#{rac_id}1"]
		vb.customize ['modifyvm', :id, '--macaddress3', "080027AAAA#{rac_id}2"]


		# Change NIC type (https://www.virtualbox.org/manual/ch06.html#nichardware)
		vb.customize ['modifyvm', :id, '--nictype1', '82545EM']      
		vb.customize ['modifyvm', :id, '--nictype2', '82545EM']  
		vb.customize ['modifyvm', :id, '--nictype3', '82545EM']  
		
		# Change RAC node specific settings 
		vb.customize ['modifyvm', :id, '--cpus', cpu]
		vb.customize ['modifyvm', :id, '--memory', mem]  

		# Increase SATA port count 
		vb.customize ['storagectl', :id, '--name', 'SATA', '--portcount', num_disks + 1]   
	 
		(1..num_disks).each do |disk|
			# Disks get created when the first node gets created
			if rac_id == 1
		    		# Only create disks on "vagrant up" and when files do not exist
				if ARGV[0] == "up" && ! File.exist?(ASM_LOC + "#{disk}.vdi")
					vb.customize ['createmedium',
								'--filename', ASM_LOC + "#{disk}.vdi",
								'--format', 'VDI',
								'--variant', 'Fixed',
								'--size', 5 * 1024]
					vb.customize ['modifyhd',
								 ASM_LOC + "#{disk}.vdi",
								'--type', 'shareable']
				end  # End if exist
				# Delete Disks on "vagrant destroy"
				if ARGV[0] == "destroy" 
					vb.customize ['closemedium', 
								ASM_LOC + "#{disk}.vdi",
								'--delete']
				end  # End if destroy
				vb.customize ['storageattach', :id,
						'--storagectl', 'SATA',
						'--port', "#{disk}",
						'--device', 0,
						'--type', 'hdd',
						'--medium', ASM_LOC + "#{disk}.vdi"]
			end # End createmedium on node 1
		end # End of EACH iterator for disks
	  
		# Workaound for Perl bug with root.sh segmentation fault
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/Leaf", "0x4"]
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/SubLeaf", "0x4"]
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/eax", "0"]
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/ebx", "0"]
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/ecx", "0"]
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/edx", "0"]
		vb.customize ['setextradata', :id, "VBoxInternal/CPUM/HostCPUID/Cache/SubLeafMask", "0xffffffff"]     
        
	end      # End of config.vm.provider
 
		if rac_id == servers
			# Start Ansible provisioning
			config.vm.provision "ansible" do |ansible|
				# ansible.verbose  = "-v"
				ansible.limit      = "all"
				ansible.playbook   = "ansible/rac_gi_db.yml"
				ansible.extra_vars = {
					devmanager:    "#{devmanager}",
					db_create_cdb: "#{db_create_cdb}",
                    db_pdb_amount: "#{db_pdb_amount}",
                    db_name:       "#{db_name}",
                    db_total_mem:  "#{db_total_mem}",
                    gi_first_node: "#{host_prefix}1",
                    gi_last_node:  "#{host_prefix}#{servers}",
                    domain_name:   "#{domain_name}"
					}
			end # End of Ansible provisioning
		end
	
    end  # End define VM config
  end # End each iterator RAC hosts
end # End of Vagrant.configure


