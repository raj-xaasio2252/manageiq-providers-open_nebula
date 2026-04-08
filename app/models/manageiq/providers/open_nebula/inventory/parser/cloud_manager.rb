class ManageIQ::Providers::OpenNebula::Inventory::Parser::CloudManager < ManageIQ::Providers::Inventory::Parser
  def parse
    availability_zones
    virtual_machines
    images
  end

  private

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
    when "POWEROFF", "STOPPED"
      "off"
    when "UNDEPLOYED"
      "off"
    when "DONE", "FAILED"
      "terminated"
    else
      "unknown"
    end
  end

 # def virtual_machines
 #   collector.vms.each do |vm|
 #     persister.vms.build(
 #       :ems_ref           => "vm-#{vm.id}",
 #       :uid_ems           => "vm-#{vm.id}",
 #       :name              => vm['NAME'],
 #       :vendor            => "unknown",
 #       :location          => "unknown",
 #       :raw_power_state   => vm.state_str,
 #       :template          => false,
 #       :availability_zone => persister.availability_zones.lazy_find("default")
 #     )
 #   end
 # end
   
  def virtual_machines
    collector.vms.each do |vm|
      cpu_count = vm['TEMPLATE/VCPU'].to_i
      cpu_count = vm['TEMPLATE/CPU'].to_i if cpu_count == 0
      memory_mb = vm['TEMPLATE/MEMORY'].to_i
      ip_address = vm['TEMPLATE/NIC/IP']

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
        :vm_or_template  => persister_vm,
        :cpu_total_cores  => cpu_count,
        :memory_mb        => memory_mb
      )

      if ip_address
        persister.networks.build(
          :hardware    => hardware,
          :description => "public",
          :ipaddress   => ip_address
        )
      end
    end
  end

  def images
    collector.images.each do |image|
      persister.miq_templates.build(
        :ems_ref         => "img-#{image.id}",
        :uid_ems         => "img-#{image.id}",
        :name            => image['NAME'],
        :vendor          => "opennebula",
        :location        => "unknown",
        :raw_power_state => "never",
        :template        => true
      )
    end
  end
end