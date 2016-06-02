$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'syskit/test/self'
require 'syskit/transformer'

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
