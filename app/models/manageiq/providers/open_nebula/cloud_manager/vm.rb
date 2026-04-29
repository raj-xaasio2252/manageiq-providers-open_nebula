class ManageIQ::Providers::OpenNebula::CloudManager::Vm < ManageIQ::Providers::CloudManager::Vm
  supports :start
  supports :stop
  supports :reboot_guest
  supports :suspend
  supports :terminate
  
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

  def raw_destroy
    with_provider_connection do |client|
      one_vm = get_one_vm(client)
      rc = one_vm.terminate(true) # true = hard terminate (works for any state)
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

   # Updated method signatures
  def remote_console_acquire_ticket_queue(protocol, userid, request_host = nil)
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
      :args        => [userid, MiqServer.my_server.id, protocol, request_host]
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def remote_console_acquire_ticket(*args)
    require 'opennebula'
    require 'securerandom'
    require 'socket'

    # args could be: [userid, originating_server_id, console_type] or with extras
    _userid              = args[0]
    _originating_server  = args[1]
    _console_type        = args[2]

    client = ext_management_system.connect
    one_vm = get_one_vm(client)

    vnc_port = one_vm['TEMPLATE/GRAPHICS/PORT']
    one_host = ext_management_system.default_endpoint.hostname

    raise MiqException::RemoteConsoleNotSupportedError,
          _("VM does not have VNC configured") if vnc_port.nil?

    proxy_port = 10000 + one_vm.id.to_i

    # Auto-detect the primary network IP (skips loopback and WSL routing IPs)
    hostname = detect_server_ip

    system("fuser -k #{proxy_port}/tcp 2>/dev/null")
    sleep 1

    pid = spawn("websockify --web #{Rails.root}/public/novnc #{proxy_port} #{one_host}:#{vnc_port}",
                [:out, :err] => "/tmp/websockify_#{one_vm.id}.log")
    Process.detach(pid)
    sleep 2

    {
      :remote_url => "http://#{hostname}:#{proxy_port}/vnc_lite.html?autoconnect=true&scale=true",
      :proto      => "remote"
    }
  end

  # Returns the first non-loopback, non-WSL-routing IPv4 address
  def detect_server_ip
    Socket.ip_address_list.each do |addr|
      next unless addr.ipv4?
      next if addr.ipv4_loopback?
      next if addr.ip_address.start_with?('10.255.')
      next if addr.ip_address.start_with?('169.254.')
      return addr.ip_address
    end

    MiqServer.my_server.ipaddress.presence ||
      MiqServer.my_server.hostname.presence ||
      '127.0.0.1'
  rescue
    '127.0.0.1'
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