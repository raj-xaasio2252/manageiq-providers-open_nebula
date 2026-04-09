class ManageIQ::Providers::OpenNebula::NetworkManager < ManageIQ::Providers::NetworkManager
  require_nested :CloudNetwork
  require_nested :CloudSubnet
  require_nested :Refresher


  include SupportsFeatureMixin

  delegate :authentication_check,
           :authentication_status,
           :authentication_status_ok?,
           :authentications,
           :authentication_for_summary,
           :zone,
           :connect,
           :verify_credentials,
           :with_provider_connection,
           :address,
           :ip_address,
           :hostname,
           :default_endpoint,
           :endpoints,
           :to        => :parent_manager,
           :allow_nil => true

  def self.hostname_required?
    false
  end

  def self.ems_type
    @ems_type ||= "open_nebula_network".freeze
  end

  def self.description
    @description ||= "OpenNebula Network".freeze
  end

  def self.display_name(number = 1)
    n_('Network Provider (OpenNebula)', 'Network Providers (OpenNebula)', number)
  end
end