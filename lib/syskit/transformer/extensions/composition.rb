module Transformer
    module CompositionExtension
        # Returns an output port object that is providing the requested
        # transformation, or nil if none can be found
        #
        # Raises TransformationPortAmbiguity if multiple ports match.
        def find_port_for_transform(from, to)
            associated_candidates = []
            type_candidates = []
            model.each_output_port do |port|
                next if !Transformer.transform_port?(port)

                if transform = find_transform_of_port(port)
                    if transform.from == from && transform.to == to
                        return port
                    elsif ((transform.from == from || !transform.from) && (transform.to == to || !transform.to))
                        associated_candidates << port
                    end
                else
                    type_candidates << port
                end
            end

            if associated_candidates.size == 1
                return associated_candidates.first
            elsif associated_candidates.size > 1
                raise TransformationPortAmbiguity.new(self, from, to, associated_candidates)
            end

            if type_candidates.size == 1
                return type_candidates.first
            elsif type_candidates.size > 1
                raise TransformationPortAmbiguity.new(self, from, to, type_candidates)
            end

            return nil
        end

        def each_transform_output
            model.each_output_port do |port|
                next if !Transformer.transform_port?(port)

                self.each_concrete_input_connection(port) do |source_task, source_port, sink_port, policy|
                    return if !(tr = source_task.model.transformer)
                    if associated_transform = tr.find_transform_of_port(source_port)
                        yield(sink_port, associated_transform.from, associated_transform.to)
                    end
                end
            end
        end

        def select_port_for_transform(port, from, to)
            port = if port.respond_to?(:to_str) then port
                   else port.name
                   end

            self.each_concrete_input_connection(port) do |source_task, source_port, sink_port, policy|
                source_task.select_port_for_transform(source_port, from, to)
                return
            end
	    nil
        end

        def find_transform_of_port(port)
            port = if port.respond_to?(:to_str) then port
                   else port.name
                   end

            self.each_concrete_input_connection(port) do |source_task, source_port, sink_port, policy|
                return source_task.find_transform_of_port(source_port)
            end
	    nil
        end
    end
end

