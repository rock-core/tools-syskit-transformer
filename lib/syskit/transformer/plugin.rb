module Transformer
    module SyskitPlugin
        # Adds the transformation producers needed to properly setup the system.
        #
        # +engine.transformer_config+ must contain the transformation configuration
        # object.
        def self.add_needed_producers(engine, tasks)
            config = Syskit.conf.transformation_manager

            tasks.each do |task|
                tr = task.model.transformer
                Transformer.debug { "computing needed static and dynamic transformations for #{task}" }

                static_transforms  = Hash.new
                dynamic_transforms = Hash.new { |h, k| h[k] = Array.new }
                tr.each_needed_transformation do |trsf|
                    from = task.selected_frames[trsf.from]
                    to   = task.selected_frames[trsf.to]
                    if !from || !to
                        # This is validated in #validate_generated_network. Just
                        # ignore here.
                        #
                        # We do that so that the :validate_network option to
                        # Engine#instanciate applies
                        next
                    end

                    self_producers = task.transform_producers.dup
                    tr.each_transform_port do |port, transform|
                        if port.kind_of?(Orocos::Spec::InputPort) && task.connected?(port.name)
                            port_from = task.selected_frames[transform.from]
                            port_to   = task.selected_frames[transform.to]
                            self_producers[[port_from, port_to]] = port
                        end
                    end

                    Transformer.debug do
                        Transformer.debug "looking for chain for #{from} => #{to} in #{task}"
                        Transformer.debug "  with local producers: #{self_producers}"
                    end
                    chain =
                        begin
                            config.transformation_chain(from, to, self_producers)
                        rescue Exception => e
                            if engine.options[:validate_network]
                                raise InvalidChain.new(task, trsf.from, from, trsf.to, to, e),
                                    "cannot find a transformation chain to produce #{from} => #{to} for #{task} (task-local frames: #{trsf.from} => #{trsf.to}): #{e.message}", e.backtrace
                            else
                                next
                            end
                        end
                    Transformer.log_pp(:debug, chain)

                    static, dynamic = chain.partition
                    Transformer.debug do
                        Transformer.debug "#{static.size} static transformations"
                        Transformer.debug "#{dynamic.size} dynamic transformations"
                        break
                    end

                    static.each do |trsf|
                        static_transforms[[trsf.from, trsf.to]] = trsf
                    end
                    dynamic.each do |dyn|
                        if dyn.producer.kind_of?(Orocos::Spec::InputPort)
                            next
                        end
                        dynamic_transforms[dyn.producer] << dyn
                    end
                end

                task.static_transforms = static_transforms.values
                dynamic_transforms.each do |producer, transformations|
                    producer_task = producer.instanciate(engine.work_plan)
                    task.should_start_after producer_task.as_plan.start_event
                    transformations.each do |dyn|
                        task.depends_on(producer_task, :role => "transformer_#{dyn.from}2#{dyn.to}")

                        out_port = producer_task.find_port_for_transform(dyn.from, dyn.to)
                        if !out_port
                            raise TransformationPortNotFound.new(producer_task, dyn.from, dyn.to)
                        end
                        producer_task.select_port_for_transform(out_port, dyn.from, dyn.to)
                        producer_task.connect_ports(task, [out_port.name, "dynamic_transformations"] => Hash.new)
                    end
                end
            end
        end

        def self.update_configuration_state(state, tasks)
            state.port_transformation_associations.clear
            state.port_frame_associations.clear
            state.static_transformations =
                Syskit.conf.transformation_manager.conf.
                    enum_for(:each_static_transform).map do |static|
                        rbs = Types::Base::Samples::RigidBodyState.invalid
                        rbs.sourceFrame = static.from
                        rbs.targetFrame = static.to
                        rbs.position = static.translation
                        rbs.orientation = static.rotation
                        rbs
                    end

            tasks.each do |task|
                tr = task.model.transformer
                task_name = task.orocos_name
                tr.each_annotated_port do |port, frame_name|
                    selected_frame = task.selected_frames[frame_name]
                    if selected_frame
                        info = Types::Transformer::PortFrameAssociation.new(
                            :task => task_name, :port => port.name, :frame => selected_frame)
                        state.port_frame_associations << info
                    else
                        Transformer.warn "no frame selected for #{frame_name} on #{task}. This is harmless for the network to run, but will make the display of #{port.name} \"in the right frame\" impossible"
                    end
                end
                tr.each_transform_port do |port, transform|
                    next if port.kind_of?(Orocos::Spec::InputPort)

                    from = task.selected_frames[transform.from]
                    to   = task.selected_frames[transform.to]
                    if from && to
                        info = Types::Transformer::PortTransformationAssociation.new(
                            :task => task_name, :port => port.name,
                            :from_frame => from, :to_frame => to)
                        state.port_transformation_associations << info
                    else
                        Transformer.warn "no frame selected for #{transform.to} on #{task}. This is harmless for the network to run, but might remove some options during display"
                    end
                end
            end
        end

        def self.instanciation_postprocessing_hook(engine, plan)
            Roby.app.using_task_library('transformer')
            Syskit.conf.use_deployment('transformer_broadcaster')
            broadcasters = plan.find_local_tasks(Transformer::Task).not_finished.to_a
            if broadcasters.empty?
                plan.add_mission(task = Transformer::Task.instanciate(plan))
            end

            # Transfer the frame mapping information from the instance specification
            # objects to the selected_frames hashes on the tasks
            tasks = plan.find_local_tasks(Syskit::Component).roots(Roby::TaskStructure::Hierarchy)
            tasks.each do |root_task|
                FramePropagation.initialize_selected_frames(root_task, Hash.new)
                FramePropagation.initialize_transform_producers(root_task, Hash.new)
                Roby::TaskStructure::Hierarchy.each_bfs(root_task, BGL::Graph::ALL) do |from, to, info|
                    FramePropagation.initialize_selected_frames(to, from.selected_frames)
                    FramePropagation.initialize_transform_producers(to, from.transform_producers)
                end
            end
        end

        def self.instanciated_network_postprocessing_hook(engine, plan, validate)
            FramePropagation.compute_frames(plan)

            transformer_tasks = plan.find_local_tasks(Syskit::TaskContext).
                find_all { |task| task.model.transformer }

            # Now find out the frame producers that each task needs, and add them to
            # the graph
            add_needed_producers(engine, transformer_tasks)
        end

        def self.deployment_postprocessing_hook(engine, plan)
            transformer_tasks = plan.find_local_tasks(Syskit::TaskContext).
                find_all { |task| task.model.transformer }

            # And update the configuration state
            update_configuration_state(plan.transformer_configuration_state[1], transformer_tasks)
            plan.transformer_configuration_state[0] = Time.now
        end

        def self.enable
            Syskit::NetworkGeneration::Engine.register_instanciation_postprocessing do |engine, plan|
                if engine.transformer_enabled?
                    instanciation_postprocessing_hook(engine, plan)
                end
            end

            Syskit::NetworkGeneration::Engine.register_instanciated_network_postprocessing do |engine, plan, validate|
                if engine.transformer_enabled?
                    instanciated_network_postprocessing_hook(engine, plan, validate)
                end
            end

            Syskit::NetworkGeneration::Engine.register_deployment_postprocessing do |engine, plan|
                if engine.transformer_enabled?
                    deployment_postprocessing_hook(engine, plan)
                end
            end

            Syskit::Component.include Transformer::ComponentExtension
            Syskit::Component.extend Transformer::ComponentModelExtension
            Syskit::TaskContext.include Transformer::TaskContextExtension
            Syskit::Composition.include Transformer::CompositionExtension
            Syskit::BoundDataService.include Transformer::BoundDataServiceExtension
            Roby::Plan.include Transformer::PlanExtension

            Syskit::Robot::DeviceInstance.include Transformer::DeviceExtension
            Syskit::Graphviz.include Transformer::GraphvizExtension
            Syskit::InstanceRequirements.include Transformer::InstanceRequirementsExtension
            Syskit::NetworkGeneration::Engine.include Transformer::EngineExtension
            Syskit::RobyApp::Configuration.include Transformer::ConfigurationExtension

            Roby.app.filter_out_patterns.push(/^#{Regexp.quote(__FILE__)}/)
        end
    end
end

