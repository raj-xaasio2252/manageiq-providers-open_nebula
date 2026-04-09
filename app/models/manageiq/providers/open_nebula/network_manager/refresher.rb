class ManageIQ::Providers::OpenNebula::NetworkManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
 def refresh
    # Network refresh is handled by CloudManager refresher
    # Just clear the error status
    @ems.each do |ems_obj|
      ems = ems_obj.kind_of?(Array) ? ems_obj.first : ems_obj
      ems.update(:last_refresh_error => nil, :last_refresh_date => Time.zone.now, :last_refresh_success_date => Time.zone.now)
    end
  end
end