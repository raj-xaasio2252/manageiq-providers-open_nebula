class ManageIQ::Providers::OpenNebula::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  def connection
    @connection ||= manager.connect
  end

  def vms
    require 'opennebula'
    vm_pool = OpenNebula::VirtualMachinePool.new(connection)
    rc = vm_pool.info(-1, -1, -1)
    raise rc.message if OpenNebula.is_error?(rc)
    vm_pool.to_a
  end

  def images
    require 'opennebula'
    image_pool = OpenNebula::ImagePool.new(connection)
    rc = image_pool.info
    raise rc.message if OpenNebula.is_error?(rc)
    image_pool.to_a
  end

  def hosts
    require 'opennebula'
    host_pool = OpenNebula::HostPool.new(connection)
    rc = host_pool.info
    raise rc.message if OpenNebula.is_error?(rc)
    host_pool.to_a
  end

  def templates
    require 'opennebula'
    tmpl_pool = OpenNebula::TemplatePool.new(connection)
    rc = tmpl_pool.info
    raise rc.message if OpenNebula.is_error?(rc)
    tmpl_pool.to_a
  end

  def virtual_networks
    require 'opennebula'
    vnet_pool = OpenNebula::VirtualNetworkPool.new(connection)
    rc = vnet_pool.info
    raise rc.message if OpenNebula.is_error?(rc)
    vnet_pool.to_a
  end
end