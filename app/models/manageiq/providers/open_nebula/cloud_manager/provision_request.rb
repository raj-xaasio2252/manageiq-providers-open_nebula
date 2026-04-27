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

  # Skip Automate events — approve and execute directly
  def post_create(_auto_approve)
    set_description

    # Auto-approve immediately
    miq_approvals.each { |a| a.approve(User.super_admin.userid, "Auto-Approved") }
    update(:approval_state => "approved")

    # Queue task creation directly (skip Automate events)
    MiqQueue.put(
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "create_request_tasks",
      :zone        => options.fetch(:miq_zone, my_zone),
      :role        => my_role(:create_request_tasks),
      :msg_timeout => 3600
    )

    self
  end
end