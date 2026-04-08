class ManageIQ::Providers::OpenNebula::CloudManager::Vm < ManageIQ::Providers::CloudManager::Vm
  supports :start
  supports :stop
  supports :reboot_guest
  supports :suspend
  supports :console do
    if raw_power_state != "on"
      _("The VM is not powered on")
    end
  end

  def ipaddresses
    hardware&.networks&.pluck(:ipaddress)&.compact || []
  end

  def ip_addresses
    ipaddresses
  end

  def primary_ip_address
    ipaddresses.first
  end

  # ---- Power Operations ----

  def raw_start
    with_provider_connection do |client|
      one_vm = get_one_vm(client)
      rc = one_vm.resume
      raise rc.message if OpenNebula.is_error?(rc)
    end
  end

  def raw_stop
    with_provider_connection do |client|
      one_vm = get_one_vm(client)
      rc = one_vm.poweroff
      raise rc.message if OpenNebula.is_error?(rc)
    end
  end

  def raw_suspend
    with_provider_connection do |client|
      one_vm = get_one_vm(client)
      rc = one_vm.suspend
      raise rc.message if OpenNebula.is_error?(rc)
    end
  end

  def raw_reboot_guest
    with_provider_connection do |client|
      one_vm = get_one_vm(client)
      rc = one_vm.reboot
      raise rc.message if OpenNebula.is_error?(rc)
    end
  end

  # ---- Console Support ----

  def console_supported?(type)
    %w[vnc VNC html5].include?(type.to_s)
  end

  def validate_remote_console_acquire_ticket(protocol, options = {})
    raise(MiqException::RemoteConsoleNotSupportedError,
          "#{protocol} protocol not enabled for this vm") unless protocol.to_sym == :html5

    raise(MiqException::RemoteConsoleNotSupportedError,
          "#{protocol} remote console requires the vm to be registered with a management system.") if ext_management_system.nil?

    options[:check_if_running] = true unless options.key?(:check_if_running)
    raise(MiqException::RemoteConsoleNotSupportedError,
          "#{protocol} remote console requires the vm to be running.") if options[:check_if_running] && state != "on"
  end

  def remote_console_acquire_ticket(_userid, _originating_server, _console_type)
    require 'opennebula'
    require 'securerandom'

    client = ext_management_system.connect
    one_vm = get_one_vm(client)

    vnc_port = one_vm['TEMPLATE/GRAPHICS/PORT']
    one_host = ext_management_system.default_endpoint.hostname

    raise MiqException::RemoteConsoleNotSupportedError,
          _("VM does not have VNC configured") if vnc_port.nil?

    the_secret = SecureRandom.hex(16)

    proxy_port = 10000 + one_vm.id.to_i

    system("fuser -k #{proxy_port}/tcp 2>/dev/null")
    sleep 1

    pid = spawn("websockify --web #{Rails.root}/public/novnc #{proxy_port} #{one_host}:#{vnc_port}",
                [:out, :err] => "/tmp/websockify_#{one_vm.id}.log")
    Process.detach(pid)
    sleep 2

    {
      :remote_url => "http://localhost:#{proxy_port}/vnc_lite.html?autoconnect=true&scale=true",
      :proto      => "remote"
    }
  end

  def remote_console_acquire_ticket_queue(protocol, userid)
    task_opts = {
      :action => "acquiring Instance #{name} #{protocol.to_s.upcase} remote console ticket for user #{userid}",
      :userid => userid
    }

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => 'remote_console_acquire_ticket',
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [userid, MiqServer.my_server.id, protocol]
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  # ---- Power State ----

  def self.calculate_power_state(raw_power_state)
    case raw_power_state
    when "on"         then "on"
    when "off"        then "off"
    when "suspended"  then "suspended"
    when "terminated" then "terminated"
    else "unknown"
    end
  end

  private

  def get_one_vm(client)
    require 'opennebula'
    one_id = ems_ref.sub("vm-", "").to_i
    one_vm = OpenNebula::VirtualMachine.new(
      OpenNebula::VirtualMachine.build_xml(one_id), client
    )
    rc = one_vm.info
    raise rc.message if OpenNebula.is_error?(rc)
    one_vm
  end

  def with_provider_connection
    require 'opennebula'
    client = ext_management_system.connect
    yield client
  end
end