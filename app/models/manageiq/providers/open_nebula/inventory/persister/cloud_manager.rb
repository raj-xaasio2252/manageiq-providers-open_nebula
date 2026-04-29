class ManageIQ::Providers::OpenNebula::Inventory::Persister::CloudManager < ManageIQ::Providers::Inventory::Persister
  def initialize_inventory_collections
    add_collection(cloud, :vms) do |builder|
      builder.add_properties(
        :model_class => ManageIQ::Providers::OpenNebula::CloudManager::Vm,
        :delete_method => :disconnect_inv
      )
    end

    add_collection(cloud, :miq_templates) do |builder|
      builder.add_properties(
        :model_class => ManageIQ::Providers::OpenNebula::CloudManager::Template,
        :delete_method => :disconnect_inv
      )
    end

    add_collection(cloud, :availability_zones) do |builder|
      builder.add_properties(:model_class => ManageIQ::Providers::OpenNebula::CloudManager::AvailabilityZone)
    end

    add_collection(cloud, :hardwares) do |builder|
      builder.add_properties(
        :manager_ref => [:vm_or_template]
      )
    end

    add_collection(cloud, :networks) do |builder|
      builder.add_properties(
        :manager_ref => [:hardware, :description]
      )
    end

    add_collection(cloud, :operating_systems) do |builder|
      builder.add_properties(
        :manager_ref => [:vm_or_template]
      )
    end

    add_collection(cloud, :disks) do |builder|
      builder.add_properties(
        :manager_ref => [:hardware, :device_name]
      )
    end 

    add_collection(cloud, :cloud_volumes) do |builder|
      builder.add_properties(
        :model_class => ::CloudVolume
      )
    end
    
  end
end