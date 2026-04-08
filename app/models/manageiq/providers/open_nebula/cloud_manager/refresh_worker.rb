class ManageIQ::Providers::OpenNebula::CloudManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  def self.settings_name
    :ems_refresh_worker_open_nebula
  end
end