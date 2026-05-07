Rails.application.config.to_prepare do
  begin
    OpenNebula::Client.class_eval do
      def inspect
        "#<#{self.class}:0x#{object_id.to_s(16)}>"
      end
    end
  rescue NameError
    nil
  end
end