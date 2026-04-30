class ManageIQ::Providers::OpenNebula::CloudManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
  def post_refresh(ems, _start_time)
    super
    link_network_ports(ems)
  end

  private

  def link_network_ports(ems)
    require 'opennebula'
    _log.info("XAAS DEBUG: post_refresh link_network_ports STARTED for EMS #{ems.id}")

    client = ems.connect
    pool = OpenNebula::VirtualMachinePool.new(client)
    rc = pool.info(-2, -1, -1)
    if OpenNebula.is_error?(rc)
      _log.warn("XAAS DEBUG: Failed to get VM pool: #{rc.message}")
      return
    end

    network_ems = ems.network_manager || ems

    pool.each do |vm|
      vm_record = Vm.find_by(:ems_ref => "vm-#{vm.id}", :ems_id => ems.id)
      next unless vm_record

      nic_index = 0
      vm.each("TEMPLATE/NIC") do |nic|
        mac_address = nic['MAC']
        vnet_id     = nic['NETWORK_ID']
        ip_address  = nic['IP']
        next if mac_address.blank?

        np = NetworkPort.find_or_initialize_by(
          :ems_ref     => "nic-vm-#{vm.id}-#{nic_index}",
          :device_id   => vm_record.id,
          :device_type => "VmOrTemplate"
        )
        np.update!(
          :name        => "nic#{nic_index}",
          :ems_id      => network_ems.id,
          :mac_address => mac_address,
          :status      => "active"
        )

        if vnet_id.present?
          subnet = CloudSubnet.find_by(
            :ems_ref => "subnet-#{vnet_id}",
            :ems_id  => network_ems.id
          )

          if subnet
            csnp = CloudSubnetNetworkPort.find_or_initialize_by(
              :network_port_id => np.id,
              :cloud_subnet_id => subnet.id
            )
            csnp.update!(:address => ip_address) if ip_address.present?

            if nic_index == 0
              vm_record.update_columns(
                :cloud_network_id => subnet.cloud_network_id,
                :cloud_subnet_id  => subnet.id
              )
              
            end
          else
          end
        end

        nic_index += 1
      end
    end
  rescue => e
 end
end
