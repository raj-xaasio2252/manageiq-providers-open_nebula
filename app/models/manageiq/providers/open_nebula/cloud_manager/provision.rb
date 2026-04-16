class ManageIQ::Providers::OpenNebula::CloudManager::Provision < ManageIQ::Providers::CloudManager::Provision

  def self.provider_model
    ManageIQ::Providers::OpenNebula::CloudManager
  end

  # Tell ManageIQ what the source class is
  def self.base_model
    ManageIQ::Providers::CloudManager::Provision
  end

  # Skip Automate state machine
  def deliver_to_automate(*)
    execute
  end

  def after_request_task_create
    update(:description => "Provision from [#{source.name}] to [#{get_option(:vm_name)}]")
  end

  def execute
    _log.info("Starting OpenNebula VM provisioning for: #{get_option(:vm_name)}")
    create_vm
    mark_as_completed
  rescue => err
    _log.error("OpenNebula provisioning failed: #{err.message}")
    _log.error(err.backtrace.join("\n"))
    update(:state => 'finished', :status => 'Error', :message => err.message)
    miq_request.update(:request_state => 'finished', :status => 'Error', :message => err.message)
  end

  def mark_as_completed
    EmsRefresh.queue_refresh(source.ext_management_system)
    update(:state => 'finished', :status => 'Ok', :message => 'VM provisioned successfully')
    miq_request.update(:request_state => 'finished', :status => 'Ok', :message => 'VM provisioned successfully')
  end

  def create_vm
    require 'opennebula'

    ems  = source.ext_management_system
    auth = ems.authentications.first

    client = OpenNebula::Client.new(
      "#{auth.userid}:#{auth.password}",
      "http://#{ems.hostname}:#{ems.port || 2633}/RPC2"
    )

    image_id = source.ems_ref.gsub('img-', '')
    vm_name  = get_option(:vm_name).to_s.strip
    vm_name  = "manageiq-vm-#{Time.now.to_i}" if vm_name.blank?

    cpus = get_option(:number_of_cpus)
    cpus = cpus.first if cpus.kind_of?(Array)
    cpus = cpus.to_i
    cpus = 1 if cpus == 0

    # VCPU (separate from CPU)
    vcpus = get_option(:number_of_vcpus)
    vcpus = vcpus.first if vcpus.kind_of?(Array)
    vcpus = vcpus.to_i
    vcpus = cpus if vcpus == 0  # Default to same as CPU if not set

    memory = get_option(:vm_memory) || get_option(:memory)
    memory = memory.first if memory.kind_of?(Array)
    memory = memory.to_i
    memory = 1024 if memory == 0

    # Network - from user selection
    network_id = get_option(:cloud_network)
    network_id = network_id.first if network_id.kind_of?(Array)
    network_id = network_id.to_i
    network_id = 1 if network_id == 0  # Fallback

    vm_definition = <<-EOF
NAME   = "#{vm_name}"
CPU    = "#{cpus}"
VCPU   = "#{cpus}"
MEMORY = "#{memory}"
DISK   = [ IMAGE_ID = "#{image_id}" ]
NIC    = [ NETWORK_ID = "#{network_id}" ]
OS     = [ ARCH = "x86_64", BOOT = "disk0" ]
GRAPHICS = [ LISTEN = "0.0.0.0", TYPE = "VNC" ]
    EOF

    _log.info("OpenNebula VM definition:\n#{vm_definition}")

    xml = OpenNebula::VirtualMachine.build_xml
    vm  = OpenNebula::VirtualMachine.new(xml, client)
    rc  = vm.allocate(vm_definition)

    if OpenNebula.is_error?(rc)
      raise MiqException::MiqProvisionError, "OpenNebula error: #{rc.message}"
    end

    _log.info("OpenNebula VM created: ID=#{vm.id} Name=#{vm_name}")
    vm.id
  end
end