class ManageIQ::Providers::OpenNebula::CloudManager::MetricsCollectorWorker < ManageIQ::Providers::BaseManager::MetricsCollectorWorker
  require_nested :Runner

  self.default_queue_name = "open_nebula"

  def friendly_name
    @friendly_name ||= "C&U Metrics Collector for ManageIQ::Providers::OpenNebula"
  end
end
