class ManageIQ::Providers::OpenNebula::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :CloudManager

  def initialize_inventory_collections
    add_cloud_collection(:vms)
  end
end
