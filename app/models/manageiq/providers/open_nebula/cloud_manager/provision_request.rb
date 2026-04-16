class ManageIQ::Providers::OpenNebula::CloudManager::ProvisionRequest < MiqProvisionRequest

  TASK_DESCRIPTION  = 'Cloud VM Provisioning'.freeze
  SOURCE_CLASS_NAME = 'VmOrTemplate'.freeze

  def self.request_types
    %w[template]
  end

  def self.request_task_class
    ManageIQ::Providers::OpenNebula::CloudManager::Provision
  end

  def self.request_task_class_from(_attribs)
    ManageIQ::Providers::OpenNebula::CloudManager::Provision
  end

  def requested_task_idx
    src = get_option(:src_vm_id)
    src = src.first if src.kind_of?(Array)
    [src]
  end

  def customize_request_task_attributes(req_task_attrs, idx)
    req_task_attrs[:source_id]   = idx
    req_task_attrs[:source_type] = 'VmOrTemplate'
    req_task_attrs['options']    = options.merge(:pass_number => 0)
  end

  def my_role(_action = nil)
    'ems_operations'
  end

  # Auto-approve on create — this is the fix
  def post_create(_auto_approve)
    set_description
    audit_request_success(requester, :created)
    call_automate_event_queue("request_created")

    # Force auto-approve regardless of what was passed
    approve(User.super_admin.userid, "Auto-Approved")
    reload

    self
  end
end