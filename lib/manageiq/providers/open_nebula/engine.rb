module ManageIQ
  module Providers
    module OpenNebula
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::OpenNebula

        config.autoload_paths << root.join('lib').to_s

        initializer :append_secrets do |app|
          app.config.paths["config/secrets"] << root.join("config", "secrets.defaults.yml").to_s
          app.config.paths["config/secrets"] << root.join("config", "secrets.yml").to_s
        end

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Open Nebula Provider')
        end

        def self.init_loggers
          $open_nebula_log ||= Vmdb::Loggers.create_logger("open_nebula.log")
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $open_nebula_log, :level_open_nebula)
        end
      end
    end
  end
end
