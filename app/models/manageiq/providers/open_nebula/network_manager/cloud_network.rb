class ManageIQ::Providers::OpenNebula::NetworkManager::CloudNetwork < ::CloudNetwork
  def self.display_name(number = 1)
    n_('Cloud Network (OpenNebula)', 'Cloud Networks (OpenNebula)', number)
  end
end