class ManageIQ::Providers::OpenNebula::Inventory::Collector::CloudManager < ManageIQ::Providers::OpenNebula::Inventory::Collector
  def vms
    @vms ||= begin
    require 'opennebula'
    vm_pool = OpenNebula::VirtualMachinePool.new(connection)
    rc = vm_pool.info(-2, -1, -1)
    raise rc.message if OpenNebula.is_error?(rc)
    vm_pool.to_a
   end
  end

  def images
    @images ||= begin
    require 'opennebula'
    image_pool = OpenNebula::ImagePool.new(connection)
    rc = image_pool.info(-2, -1, -1)
    raise rc.message if OpenNebula.is_error?(rc)
    image_pool.to_a
   end
  end

  def connection
    @connection ||= manager.connect
  end
end