class ManageIQ::Providers::OpenNebula::CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
     def refresh
    result = super

    # Create network ports after VMs are saved
    @ems.each do |ems_entry|
      ems = ems_entry.kind_of?(Array) ? ems_entry.first : ems_entry
      next unless ems.kind_of?(ManageIQ::Providers::OpenNebula::CloudManager)
      create_network_ports(ems)
    end

    result
  end

  private

  def create_network_ports(ems)
    require 'opennebula'
    client = ems.connect
    pool = OpenNebula::VirtualMachinePool.new(client)
    rc = pool.info(-2, -1, -1)
    return if OpenNebula.is_error?(rc)

    network_ems = ems.network_manager || ems

    pool.each do |vm|
      mac_address = vm['TEMPLATE/NIC/MAC']
      vnet_id = vm['TEMPLATE/NIC/NETWORK_ID']
      next if mac_address.blank?

      vm_record = Vm.find_by(:ems_ref => "vm-#{vm.id}", :ems_id => ems.id)
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
        subnet = CloudSubnet.find_by(
          :ems_ref => "subnet-#{vnet_id}",
          :ems_id  => network_ems.id
        )
        if subnet && !np.cloud_subnets.include?(subnet)
          np.cloud_subnets << subnet
        end
      end
    end
  rescue => e
    _log.warn("Post-refresh network ports error: #{e.message}")
  end
end
