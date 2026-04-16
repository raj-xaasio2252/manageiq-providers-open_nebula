class ManageIQ::Providers::OpenNebula::CloudManager::ProvisionWorkflow < ManageIQ::Providers::CloudManager::ProvisionWorkflow

  def self.provider_model
    ManageIQ::Providers::OpenNebula::CloudManager
  end

  def self.default_dialog_file
    'miq_provision_open_nebula_dialogs_template'
  end

  # Tell workflow to create OpenNebula ProvisionRequest (not plain MiqProvisionRequest)
  def self.request_class
    ManageIQ::Providers::OpenNebula::CloudManager::ProvisionRequest
  end

  def dialog_name_from_automate(_message = 'get_dialog_name', _extra_attrs = {})
    'miq_provision_open_nebula_dialogs_template'
  end

  # Override to skip parent's sysprep/networking field initialization
  def init_from_dialog(init_values)
    @dialogs = get_dialogs
    @values  = init_values

    @dialogs[:dialogs].each do |_dname, dialog|
      next unless dialog[:fields]
      dialog[:fields].each do |field_name, field_def|
        next if @values.key?(field_name)
        @values[field_name] = field_def[:default] if field_def.key?(:default)
      end
    end
  end

  # Override methods the parent calls but don't apply to OpenNebula
  def update_field_visibility; end
  def set_default_values; end
  def validate_memory_reservation(_field, _values, _dlg, _fld, _value); end

  # Provide source VM/template info
  def get_source_and_targets(options = {})
    src = @values[:src_vm_id]
    return {} if src.blank?

    vm_id    = src.kind_of?(Array) ? src.first : src
    template = MiqTemplate.find_by(:id => vm_id)
    return {} if template.nil?

    {
      :vm  => template,
      :ems => template.ext_management_system
    }
  end

  def allowed_images(options = {})
    ManageIQ::Providers::OpenNebula::CloudManager::Template
      .where.not(:ems_id => nil)
      .each_with_object({}) do |img, hash|
        hash[img.id] = {:name => img.name, :id => img.id}
      end
  end

  def allowed_instance_types(options = {})
    {}
  end

  #def allowed_cloud_networks(options = {})
  #  src = get_source_and_targets
  #  ems = src[:ems]
  #  return {} if ems.nil?

   # CloudNetwork.where(:ems_id => ems.id).each_with_object({}) do |cn, hash|
   #   hash[cn.id] = {:name => cn.name, :id => cn.id}
   # end
  #end
  
  def allowed_cloud_networks(options = {})
  ems_id = ManageIQ::Providers::OpenNebula::CloudManager.first.try(:id)
  return {} if ems_id.nil?

  # Fetch cloud networks from the associated Network Manager
  network_manager_id = ManageIQ::Providers::OpenNebula::NetworkManager
                         .where(:parent_ems_id => ems_id)
                         .first.try(:id)

  return {} if network_manager_id.nil?

  CloudNetwork.where(:ems_id => network_manager_id).each_with_object({}) do |cn, hash|
    # ems_ref in OpenNebula is like "vnet-1" — extract the numeric ID
    network_id = cn.ems_ref.to_s.gsub(/\D/, '').to_i
    hash[network_id] = {:name => cn.name, :id => network_id}
  end
end

  def allowed_cloud_tenants(options = {})
    {}
  end

  def allowed_availability_zones(options = {})
    {}
  end

  def allowed_security_groups(options = {})
    {}
  end

  def allowed_floating_ip_addresses(options = {})
    {}
  end

  def allowed_key_pairs(options = {})
    {}
  end

  def allowed_guest_access_key_pairs(options = {})
    {}
  end

  def allowed_number_of_cpus(options = {})
    {1 => "1", 2 => "2", 4 => "4", 8 => "8", 16 => "16"}
  end

  def allowed_vm_memory(options = {})
    {"512" => "512", "1024" => "1024", "2048" => "2048", "4096" => "4096", "8192" => "8192", "16384" => "16384"}
  end

  def make_request(old_request, values, requester = nil)
    values[:src_vm_id] = [values[:src_vm_id], MiqTemplate.find(values[:src_vm_id].kind_of?(Array) ? values[:src_vm_id].first : values[:src_vm_id]).name] unless values[:src_vm_id].kind_of?(Array)
    super
  end
end