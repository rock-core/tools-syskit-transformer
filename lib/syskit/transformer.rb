require 'utilrb/logger/root'
module Syskit::Transformer
    extend Logger::Root('Syskit::Transformer', Logger::WARN)
end

require 'rgl/traversal'
require 'syskit/transformer/configuration'
require 'syskit/transformer/exceptions'
require 'syskit/transformer/extensions'
require 'syskit/transformer/frame_propagation'
require 'syskit/transformer/plugin'
