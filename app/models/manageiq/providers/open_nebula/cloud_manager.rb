class ManageIQ::Providers::OpenNebula::CloudManager < ManageIQ::Providers::CloudManager
  supports :create

  def self.ems_type
    @ems_type ||= "open_nebula".freeze
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
    url    = "http://#{hostname}:#{port}/RPC2"
    client = OpenNebula::Client.new("#{userid}:#{password}", url)
    user_pool = OpenNebula::UserPool.new(client)
    rc = user_pool.info
    raise MiqException::MiqInvalidCredentialsError, rc.message if OpenNebula.is_error?(rc)
    client
  end

  def connect(options = {})
    self.class.raw_connect(
      default_endpoint.hostname,
      default_endpoint.port || 2633,
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