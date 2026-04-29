class ManageIQ::Providers::OpenNebula::Inventory::Parser::CloudManager < ManageIQ::Providers::Inventory::Parser
  def parse
    availability_zones
    virtual_machines
    images
    cloud_networks
    cloud_volumes
  end

  def after_persist
    link_network_ports
  end

  private

  def link_network_ports
    ems = collector.manager
    require 'opennebula'
    client = ems.connect
    pool = OpenNebula::VirtualMachinePool.new(client)
    rc = pool.info(-2, -1, -1)
    return if OpenNebula.is_error?(rc)

    network_ems = ems.network_manager || ems

    pool.each do |vm|
      mac_address = vm['TEMPLATE/NIC/MAC']
      vnet_id     = vm['TEMPLATE/NIC/NETWORK_ID']
      ip_address  = vm['TEMPLATE/NIC/IP']
      next if mac_address.blank?

      vm_record = Vm.find_by(:ems_ref => "vm-#{vm.id}", :ems_id => ems.id)
      next unless vm_record

      # Find or create network port
      np = NetworkPort.find_or_initialize_by(
        :ems_ref    => "nic-vm-#{vm.id}-0",
        :device_id  => vm_record.id,
        :device_type => "VmOrTemplate"
      )
      np.update!(
        :name        => "nic0",
        :ems_id      => network_ems.id,
        :mac_address => mac_address,
        :status      => "active"
      )

      next unless vnet_id.present?

      subnet = CloudSubnet.find_by(
        :ems_ref => "subnet-#{vnet_id}",
        :ems_id  => network_ems.id
      )
      next unless subnet

      # Link network port to subnet
      csnp = CloudSubnetNetworkPort.find_or_initialize_by(
        :network_port_id => np.id,
        :cloud_subnet_id => subnet.id
      )
      csnp.update!(:address => ip_address) if ip_address.present?

      # Also update VM cloud_network_id directly for list view
      vm_record.update_columns(
        :cloud_network_id => subnet.cloud_network_id,
        :cloud_subnet_id  => subnet.id
      )
    end
  rescue => e
    _log.warn("Network ports linking error: #{e.message}")
    _log.warn(e.backtrace.join("\n"))
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
        :vm_or_template     => persister_vm,
        :cpu_total_cores    => cpu_count,
        :memory_mb          => memory_mb,
        :guest_os           => guest_os,
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
    when /ubuntu/i                 then "Ubuntu"
    when /centos\s*(\d+[\.\d]*)/i  then "CentOS #{$1}"
    when /centos/i                 then "CentOS"
    when /rhel|red\s*hat/i         then "Red Hat Enterprise Linux"
    when /debian\s*(\d+[\.\d]*)/i  then "Debian #{$1}"
    when /debian/i                 then "Debian"
    when /fedora/i                 then "Fedora"
    when /suse|sles/i              then "SUSE Linux"
    when /windows\s*server/i       then "Windows Server"
    when /windows/i                then "Windows"
    when /alma/i                   then "AlmaLinux"
    when /rocky/i                  then "Rocky Linux"
    when /oracle/i                 then "Oracle Linux"
    when /arch/i                   then "Arch Linux"
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
      image_format  = image['FORMAT'].presence || 'raw'
      guest_os      = detect_guest_os(image['NAME'])

      hardware = persister.hardwares.build(
        :vm_or_template     => persister_template,
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
  end

  def cloud_networks
    collector.vnets.each do |vnet|
      vnet_id     = vnet.id
      vnet_name   = vnet['NAME']
      vlan_id     = vnet['VLAN_ID']
      vn_mad      = vnet['VN_MAD']
      subnet_mask = vnet['TEMPLATE/NETWORK_MASK']
      gateway     = vnet['TEMPLATE/GATEWAY']

      cidr = calculate_cidr(gateway, subnet_mask)

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
  
  def cloud_volumes
    collector.datastores.each do |ds|
      type_name = case ds['TYPE'].to_s
                  when '0' then 'Image'
                  when '1' then 'System'
                  when '2' then 'File'
                  else 'Unknown'
                  end

      persister.cloud_volumes.build(
        :ems_ref     => "ds-#{ds.id}",
        :name        => ds.name,
        :status      => ds['STATE'].to_s == '0' ? 'available' : 'disabled',
        :size        => ds['TOTAL_MB'].to_i * 1.megabyte,
        :description => "#{type_name} datastore (DS_MAD: #{ds['DS_MAD']}, TM_MAD: #{ds['TM_MAD']})",
        :volume_type => type_name
      )
    end
  end
end