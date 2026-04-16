module ManageIQ::Providers::OpenNebula::CloudManager::Provision::Cloning
  # Mirror of OpenStack: find the provisioned VM in ManageIQ's DB by its ems_ref
  def find_destination_in_vmdb(ems_ref)
    super
  rescue NoMethodError => ex
    _log.debug("Unable to find Provision Source EMS: #{ex}")
    vm_model_class.find_by(:ems_id => options[:src_ems_id].try(:first), :ems_ref => ems_ref)
  end

  # Mirror of OpenStack: poll until VM is RUNNING, raise on failure
  # OpenStack checks instance.state == :active
  # OpenNebula: LCM_STATE 3 = RUNNING, STATE 7 = FAILED
  def do_clone_task_check(clone_task_ref)
    source.with_provider_connection do |one_client|
      result = one_client.call("one.vm.info", clone_task_ref.to_i)
      raise MiqException::MiqProvisionError, "OpenNebula error: #{result[1]}" unless result[0]

      xml   = Nokogiri::XML(result[1])
      state = xml.at_xpath("//STATE")&.text.to_i
      lcm   = xml.at_xpath("//LCM_STATE")&.text.to_i

      if state == 7 # FAILED
        raise MiqException::MiqProvisionError,
              "An error occurred while provisioning Instance #{dest_name}: VM entered FAILED state"
      end

      return true if state == 3 && lcm == 3  # ACTIVE + RUNNING

      return false, "state=#{state} lcm_state=#{lcm}"
    end
  end

  # Mirror of OpenStack's prepare_for_clone_task:
  # Build the options hash that gets passed into start_clone
  def prepare_for_clone_task
    clone_options = super  # picks up :vm_name, basic fields from MiqProvisionCloud

    clone_options[:name]        = dest_name
    clone_options[:template_id] = source.ems_ref.to_i  # the OpenNebula Template ID
    clone_options[:cpu]         = get_option(:number_of_cpus).to_i
    clone_options[:memory]      = get_option(:vm_memory).to_i   # MB

    # Network — equivalent of OpenStack's configure_network_adapters
    network_id = get_option(:cloud_network)
    clone_options[:nics] = [{ :network_id => network_id }] if network_id.present?

    clone_options
  end

  # Mirror of OpenStack's log_clone_options
  def log_clone_options(clone_options)
    _log.info("Provisioning [#{source.name}] to [#{clone_options[:name]}]")
    _log.info("Source Template ID: [#{clone_options[:template_id]}]")
    _log.info("CPU: [#{clone_options[:cpu]}]  Memory: [#{clone_options[:memory]}MB]")
    _log.info("Network: [#{clone_options[:nics]}]")
    dump_obj(clone_options, "#{_log.prefix} Clone Options: ", $log, :info)
    dump_obj(options, "#{_log.prefix} Prov Options: ", $log, :info,
             :protected => {:path => workflow_class.encrypted_options_field_regs})
  end

  # Mirror of OpenStack's start_clone:
  # OpenStack → openstack.servers.create(clone_options)
  # OpenNebula → one.template.instantiate(template_id, name, on_hold, extra_xml, persistent)
  def start_clone(clone_options)
    source.with_provider_connection do |one_client|
      extra_xml = build_merge_template(clone_options)

      result = one_client.call(
        "one.template.instantiate",
        clone_options[:template_id],  # INT  — template to instantiate
        clone_options[:name],          # STR  — name for the new VM
        false,                         # BOOL — start on hold?
        extra_xml,                     # STR  — merge template overrides
        false                          # BOOL — create as persistent?
      )

      unless result[0]
        raise MiqException::MiqProvisionError,
              "An error occurred while provisioning Instance #{clone_options[:name]}: #{result[1]}"
      end

      result[1].to_s  # returns the new VM's ID — stored as ems_ref
    end
  rescue MiqException::MiqProvisionError
    raise
  rescue => e
    raise MiqException::MiqProvisionError,
          "An error occurred while provisioning Instance #{clone_options[:name]}: #{e.message}",
          e.backtrace
  end

  private

  # Builds the XML merged into the template at instantiation time.
  # This is how OpenNebula lets you override CPU/memory/NICs per-VM
  # without modifying the base template — equivalent to OpenStack's
  # flavor_ref + nics being separate params on servers.create.
  def build_merge_template(clone_options)
    nics_xml = Array(clone_options[:nics]).map do |nic|
      "<NIC><NETWORK_ID>#{nic[:network_id]}</NETWORK_ID></NIC>"
    end.join

    <<~XML
      <TEMPLATE>
        <CPU>#{clone_options[:cpu]}</CPU>
        <MEMORY>#{clone_options[:memory]}</MEMORY>
        #{nics_xml}
      </TEMPLATE>
    XML
  end
end