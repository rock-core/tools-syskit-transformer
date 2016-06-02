module Syskit::Transformer
    # Module used to extend the device specification objects with the ability
    # to specify frames
    #
    # The #frame attribute allows to specify in which frame this device
    # produces information.
    module MasterDeviceExtension
        ## 
        # Provide transform assignments for the underlying device driver
        def use_frames(frame_mappings)
            requirements.use_frames(frame_mappings)
            self
        end

        # Device-level transformer configuration
        #
        # @overload transformer { }
        #   Provides transformer configuration specific to this device
        #
        #   @returns [self]
        #
        # @overload transformer
        #   Returns the transformer configuration specific to this device
        #
        #   @returns [Transformer::Configuration]
        def transformer(&block)
            if block_given?
                requirements.transformer(&block)
                self
            else
                requirements.transformer
            end
        end
    end
end
