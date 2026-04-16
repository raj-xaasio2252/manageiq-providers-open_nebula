class ManageIQ::Providers::OpenNebula::CloudManager::Template < ManageIQ::Providers::CloudManager::Template
  supports :provisioning

  def self.provision_class(_via)
    ManageIQ::Providers::OpenNebula::CloudManager::Provision
  end
end