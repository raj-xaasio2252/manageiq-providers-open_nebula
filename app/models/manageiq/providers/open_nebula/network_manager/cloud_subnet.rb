class ManageIQ::Providers::OpenNebula::NetworkManager::CloudSubnet < ::CloudSubnet
  def self.display_name(number = 1)
    n_('Cloud Subnet (OpenNebula)', 'Cloud Subnets (OpenNebula)', number)
  end
end