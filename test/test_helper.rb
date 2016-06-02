$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'syskit/test/self'
require 'syskit/transformer'

if ENV['TEST_LOG_LEVEL']
    Syskit::Transformer.logger.level = Logger.const_get(ENV['TEST_LOG_LEVEL'])
elsif (ENV['TEST_ENABLE_COVERAGE'] == '1') || rand > 0.5
    null_io = File.open('/dev/null', 'w')
    current_formatter = Syskit::Transformer.logger.formatter
    Syskit::Transformer.warn "running tests with logger in DEBUG mode"
    Syskit::Transformer.logger = Logger.new(null_io)
    Syskit::Transformer.logger.level = Logger::DEBUG
    Syskit::Transformer.logger.formatter = current_formatter
else
    Syskit::Transformer.warn "running tests with logger in FATAL mode"
    Syskit::Transformer.logger.level = Logger::FATAL + 1
end


module Syskit::Transformer
    module Plugin
        module SelfTest
            def setup
                super
                Orocos.export_types = true
                Syskit.conf.transformer_warn_about_unset_frames = false
                Syskit.conf.transformer_enabled = true
            end
        end
        Minitest::Test.include SelfTest
    end
end
