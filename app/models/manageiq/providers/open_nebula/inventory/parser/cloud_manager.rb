class ManageIQ::Providers::OpenNebula::Inventory::Parser::CloudManager < ManageIQ::Providers::Inventory::Parser
  def parse
    availability_zones
    virtual_machines
    images
    cloud_networks
  end

  def after_persist
    create_network_ports
  end

  private

  def create_network_ports
    collector.vms.each do |vm|
      mac_address = vm['TEMPLATE/NIC/MAC']
      vnet_id = vm['TEMPLATE/NIC/NETWORK_ID']

      next if mac_address.blank?

      vm_record = Vm.find_by(:ems_ref => "vm-#{vm.id}", :ems_id => collector.manager.id)
      next unless vm_record

      np = NetworkPort.find_or_initialize_by(
        :ems_ref => "nic-vm-#{vm.id}-0",
        :device  => vm_record
      )
      np.update!(
        :name        => "nic0",
        :mac_address => mac_address,
        :status      => "active"
      )

      if vnet_id.present?
        network_ems = collector.manager.network_manager || collector.manager
        subnet = CloudSubnet.find_by(
          :ems_ref => "subnet-#{vnet_id}",
          :ems_id  => network_ems.id
        )
        if subnet && !np.cloud_subnets.include?(subnet)
          np.cloud_subnets << subnet
        end
      end
    end
  end

  def availability_zones
    persister.availability_zones.build(
      :ems_ref => "default",
      :name    => "Default Availability Zone"
    )
  end

  def power_state_map(state)
    case state.to_s.upcase
    when "RUNNING", "ACTIVE"
      "on"
    when "SUSPENDED", "HOLD"
      "suspended"
    when "POWEROFF", "STOPPED", "UNDEPLOYED"
      "off"
    when "DONE", "FAILED"
      "terminated"
    else
      "unknown"
    end
  end

  def virtual_machines
    collector.vms.each do |vm|
      cpu_count   = vm['TEMPLATE/VCPU'].to_i
      cpu_count   = vm['TEMPLATE/CPU'].to_i if cpu_count.zero?
      memory_mb   = vm['TEMPLATE/MEMORY'].to_i
      ip_address  = vm['TEMPLATE/NIC/IP']
      mac_address = vm['TEMPLATE/NIC/MAC']
      disk_image  = vm['TEMPLATE/DISK/IMAGE'] || ''

      guest_os = detect_guest_os(disk_image)

      persister_vm = persister.vms.build(
        :ems_ref           => "vm-#{vm.id}",
        :uid_ems           => "vm-#{vm.id}",
        :name              => vm['NAME'],
        :vendor            => "opennebula",
        :location          => "unknown",
        :raw_power_state   => power_state_map(vm.state_str),
        :template          => false,
        :availability_zone => persister.availability_zones.lazy_find("default")
      )

      hardware = persister.hardwares.build(
        :vm_or_template    => persister_vm,
        :cpu_total_cores   => cpu_count,
        :memory_mb         => memory_mb,
        :guest_os          => guest_os,
        :guest_os_full_name => "#{guest_os} (#{vm['TEMPLATE/OS/ARCH'] || 'x86_64'})"
      )

      persister.operating_systems.build(
        :vm_or_template => persister_vm,
        :product_name   => guest_os,
        :product_type   => guest_os_family(guest_os)
      )

      disk_size_mb = vm['TEMPLATE/DISK/SIZE'].to_i
      if disk_size_mb > 0
        persister.disks.build(
          :hardware        => hardware,
          :device_name     => "disk0",
          :device_type     => "disk",
          :controller_type => "virtio",
          :size            => disk_size_mb.megabytes,
          :location        => "vm-#{vm.id}-disk0"
        )
      end

      if mac_address.present?
      vm_record = Vm.find_by(:ems_ref => "vm-#{vm.id}", :ems_id => collector.manager.id)
      if vm_record
        NetworkPort.find_or_initialize_by(
          :ems_ref     => "nic-vm-#{vm.id}-0",
          :device      => vm_record
        ).update!(
          :name        => "nic0",
          :mac_address => mac_address,
          :status      => "active"
        )
      end
    end

      if ip_address.present?
        persister.networks.build(
          :hardware    => hardware,
          :description => "public",
          :ipaddress   => ip_address
        )
      end
    end
  end

  def detect_guest_os(image_name)
    name = image_name.to_s.downcase

    case name
    when /ubuntu\s*(\d+[\.\d]*)/i then "Ubuntu #{$1}"
    when /ubuntu/i                then "Ubuntu"
    when /centos\s*(\d+[\.\d]*)/i then "CentOS #{$1}"
    when /centos/i                then "CentOS"
    when /rhel|red\s*hat/i        then "Red Hat Enterprise Linux"
    when /debian\s*(\d+[\.\d]*)/i then "Debian #{$1}"
    when /debian/i                then "Debian"
    when /fedora/i                then "Fedora"
    when /suse|sles/i             then "SUSE Linux"
    when /windows\s*server/i      then "Windows Server"
    when /windows/i               then "Windows"
    when /alma/i                  then "AlmaLinux"
    when /rocky/i                 then "Rocky Linux"
    when /oracle/i                then "Oracle Linux"
    when /arch/i                  then "Arch Linux"
    else
      image_name.presence || "Unknown"
    end
  end

  def guest_os_family(os_name)
    case os_name.to_s.downcase
    when /windows/
      "windows"
    else
      "linux"
    end
  end
  
  def images
  collector.images.each do |image|
    persister_template = persister.miq_templates.build(
      :ems_ref         => "img-#{image.id}",
      :uid_ems         => "img-#{image.id}",
      :name            => image['NAME'],
      :vendor          => "opennebula",
      :location        => "unknown",
      :raw_power_state => "never",
      :template        => true
    )

    image_size_mb = image['SIZE'].to_i
    image_format = image['FORMAT'].presence || 'raw'
    guest_os = detect_guest_os(image['NAME'])

    hardware = persister.hardwares.build(
      :vm_or_template    => persister_template,
      :guest_os           => guest_os,
      :guest_os_full_name => guest_os,
      :root_device_type   => image_format
    )

    if image_size_mb > 0
      persister.disks.build(
        :hardware        => hardware,
        :device_name     => "disk0",
        :device_type     => "disk",
        :controller_type => "virtio",
        :size            => image_size_mb.megabytes,
        :location        => "img-#{image.id}-disk0"
      )
    end
  end

   def cloud_networks
    collector.vnets.each do |vnet|
    vnet_id = vnet.id
    vnet_name = vnet['NAME']
    vlan_id = vnet['VLAN_ID']
    vn_mad = vnet['VN_MAD']
    subnet_mask = vnet['TEMPLATE/NETWORK_MASK']
    gateway = vnet['TEMPLATE/GATEWAY']
    dns = vnet['TEMPLATE/DNS']

    cidr = calculate_cidr(gateway, subnet_mask)

    # Use network_manager if available
    network_ems = collector.manager.network_manager || collector.manager

    network = ManageIQ::Providers::OpenNebula::NetworkManager::CloudNetwork.find_or_initialize_by(
      :ems_ref => "vnet-#{vnet_id}",
      :ems_id  => network_ems.id
    )
    network.update!(
      :name                     => vnet_name,
      :status                   => "active",
      :enabled                  => true,
      :shared                   => false,
      :provider_network_type    => vn_mad,
      :provider_segmentation_id => vlan_id
    )

    ManageIQ::Providers::OpenNebula::NetworkManager::CloudSubnet.find_or_initialize_by(
      :ems_ref => "subnet-#{vnet_id}",
      :ems_id  => network_ems.id
    ).update!(
      :name             => "#{vnet_name}-subnet",
      :cloud_network    => network,
      :cidr             => cidr,
      :gateway          => gateway,
      :dhcp_enabled     => false,
      :network_protocol => "ipv4",
      :status           => "active"
    )
  end
end
  
def calculate_cidr(ip, subnet_mask)
  return nil if ip.blank? || subnet_mask.blank?
  begin
    prefix = IPAddr.new(subnet_mask).to_i.to_s(2).count('1')
    "#{ip}/#{prefix}"
  rescue
    nil
  end
end

 end
end