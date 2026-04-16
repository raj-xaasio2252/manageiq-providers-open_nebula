class ManageIQ::Providers::OpenNebula::CloudManager < ManageIQ::Providers::CloudManager
  require_nested :Provision
  require_nested :ProvisionWorkflow
  require_nested :ProvisionRequest

  supports :create
  supports :catalog
  supports :provisioning

  has_one :network_manager,
        :foreign_key => :parent_ems_id,
        :class_name  => "ManageIQ::Providers::OpenNebula::NetworkManager",
        :autosave    => true,
        :dependent   => :destroy

  after_create :ensure_network_manager

  def self.vm_vendor
    "opennebula"
  end

  def self.provision_class(_via)
    ManageIQ::Providers::OpenNebula::CloudManager::Provision
  end

  def self.provision_workflow_class
    ManageIQ::Providers::OpenNebula::CloudManager::ProvisionWorkflow
  end

  def self.provision_request_class
    ManageIQ::Providers::OpenNebula::CloudManager::ProvisionRequest
  end

  def ensure_network_manager
    build_network_manager(:zone => zone, :name => "#{name} Network Manager") unless network_manager
    network_manager.save! if network_manager.changed?
  end

  def self.ems_type
    @ems_type ||= "opennebula".freeze
  end

  def self.description
    @description ||= "OpenNebula".freeze
  end

  def self.hostname_required?
    true
  end

  def self.vendor
    "open_nebula"
  end

  def self.params_for_create
    {
      :fields => [
        {
          :component => "sub-form",
          :id        => "endpoints-subform",
          :name      => "endpoints-subform",
          :title     => _("Endpoints"),
          :fields    => [
            {
              :component              => "validate-provider-credentials",
              :id                     => "authentications.default.valid",
              :name                   => "authentications.default.valid",
              :skipSubmit             => true,
              :isRequired             => true,
              :validationDependencies => %w[type zone_id],
              :fields                 => [
                {
                  :component  => "text-field",
                  :id         => "endpoints.default.hostname",
                  :name       => "endpoints.default.hostname",
                  :label      => _("Hostname or IP"),
                  :isRequired => true,
                  :validate   => [{:type => "required"}]
                },
                {
                  :component    => "text-field",
                  :id           => "endpoints.default.port",
                  :name         => "endpoints.default.port",
                  :label        => _("API Port"),
                  :type         => "number",
                  :initialValue => 9869
                },
                {
                  :component  => "text-field",
                  :id         => "authentications.default.userid",
                  :name       => "authentications.default.userid",
                  :label      => _("Username"),
                  :isRequired => true,
                  :validate   => [{:type => "required"}]
                },
                {
                  :component  => "password-field",
                  :id         => "authentications.default.password",
                  :name       => "authentications.default.password",
                  :label      => _("Password"),
                  :type       => "password",
                  :isRequired => true,
                  :validate   => [{:type => "required"}]
                }
              ]
            }
          ]
        }
      ]
    }
  end

  def self.verify_credentials(args)
    endpoint = args.dig("endpoints", "default")
    auth     = args.dig("authentications", "default")

    hostname = endpoint&.dig("hostname")
    port     = endpoint&.dig("port") || 9869
    userid   = auth&.dig("userid")
    password = ManageIQ::Password.try_decrypt(auth&.dig("password"))

    !!raw_connect(hostname, port, userid, password)
  end

  def self.raw_connect(hostname, port, userid, password)
    require 'opennebula'
    port = port.to_i
    if port == 2633
      url = "http://#{hostname}:#{port}/RPC2"
    else
      url = "http://#{hostname}:#{port}/"
    end
    client = OpenNebula::Client.new("#{userid}:#{password}", url)
    user_pool = OpenNebula::UserPool.new(client)
    rc = user_pool.info
    raise MiqException::MiqInvalidCredentialsError, rc.message if OpenNebula.is_error?(rc)
    client
  end

  def connect(options = {})
    self.class.raw_connect(
      default_endpoint.hostname,
      default_endpoint.port,
      authentication_userid,
      authentication_password
    )
  end

  def verify_credentials(auth_type = nil, options = {})
    connect
    true
  rescue => err
    raise MiqException::MiqInvalidCredentialsError, err.message
  end
end
