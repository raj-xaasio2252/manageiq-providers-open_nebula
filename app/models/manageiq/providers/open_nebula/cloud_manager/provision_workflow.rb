class ManageIQ::Providers::OpenNebula::CloudManager::ProvisionWorkflow < ManageIQ::Providers::CloudManager::ProvisionWorkflow

  def self.provider_model
    ManageIQ::Providers::OpenNebula::CloudManager
  end

  def self.default_dialog_file
    'miq_provision_open_nebula_dialogs_template'
  end

  def self.request_class
    ManageIQ::Providers::OpenNebula::CloudManager::ProvisionRequest
  end

  def dialog_name_from_automate(_message = 'get_dialog_name', _extra_attrs = {})
    'miq_provision_open_nebula_dialogs_template'
  end

  # ============================================================
  # ✅ THE REAL FIX: Skip pre-dialog pass = single click
  # ============================================================
  def initialize(values, requester, options = {})
    options[:use_pre_dialog] = false
    super
  end

  # ============================================================
  # ✅ SAFE: Pre-dialog values (lightweight injection)
  # ============================================================
  def get_pre_dialog_values
    values = super
    values[:owner_email] ||= User.current_user&.email.to_s
    values
  end

  # ============================================================
  # ✅ SAFE FIX: Do NOT break MIQ internal structure
  # ============================================================
  def init_from_dialog(init_values)
    super

    @values ||= {}

    # ✅ Email autofill (safe)
    if @values[:owner_email].blank?
      @values[:owner_email] = User.current_user&.email.to_s
    end
  end

  # ============================================================
  # Safe overrides
  # ============================================================
  def update_field_visibility; end
  def set_default_values; end
  def validate_memory_reservation(_field, _values, _dlg, _fld, _value); end

  # ============================================================
  # Source VM + EMS
  # ============================================================
  def get_source_and_targets(_options = {})
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

  # ============================================================
  # Templates
  # ============================================================
  def allowed_images(_options = {})
    ManageIQ::Providers::OpenNebula::CloudManager::Template
      .where.not(:ems_id => nil)
      .each_with_object({}) do |img, hash|
        hash[img.id] = img.name
      end
  end

  # ============================================================
  # Networks
  # ============================================================
  def allowed_cloud_networks(_options = {})
    ems = ManageIQ::Providers::OpenNebula::CloudManager.first
    return {} if ems.nil?

    network_manager = ems.network_manager
    return {} if network_manager.nil?

    network_manager.cloud_networks.each_with_object({}) do |net, hash|
      hash[net.id] = net.name
    end
  end

  # ============================================================
  # Other stubs
  # ============================================================
  def allowed_instance_types(_options = {}); {}; end
  def allowed_cloud_tenants(_options = {}); {}; end
  def allowed_availability_zones(_options = {}); {}; end
  def allowed_security_groups(_options = {}); {}; end
  def allowed_floating_ip_addresses(_options = {}); {}; end
  def allowed_key_pairs(_options = {}); {}; end
  def allowed_guest_access_key_pairs(_options = {}); {}; end

  def allowed_number_of_cpus(_options = {})
    {
      1  => "1",
      2  => "2",
      4  => "4",
      8  => "8",
      16 => "16"
    }
  end

  def allowed_vm_memory(_options = {})
    {
      512   => "512 MB",
      1024  => "1 GB",
      2048  => "2 GB",
      4096  => "4 GB",
      8192  => "8 GB",
      16384 => "16 GB",
      32768 => "32 GB",
      65536 => "64 GB"
    }
  end

  # ============================================================
  # Request handling
  # ============================================================
  def make_request(old_request, values, requester = nil)
    unless values[:src_vm_id].kind_of?(Array)
      vm = MiqTemplate.find(values[:src_vm_id])
      values[:src_vm_id] = [values[:src_vm_id], vm.name]
    end

    super
  end
end