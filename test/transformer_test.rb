require 'test_helper'

module Syskit::Transformer
    describe Transformer do
        describe "the handling of devices" do
            before do
                Roby.app.import_types_from 'base'
                Roby.app.import_types_from 'transformer'
            end

            describe "transform producers" do
                attr_reader :dev_m, :task_m, :dev
                before do
                    @dev_m = Syskit::Device.new_submodel do
                        output_port 'trsf', 'base/samples/RigidBodyState'
                    end
                    @task_m = Syskit::TaskContext.new_submodel do
                        output_port 'transform', 'base/samples/RigidBodyState'
                        transformer do
                            transform_output 'transform', 'from' => 'to'
                            max_latency 0.1
                        end
                    end
                    task_m.driver_for dev_m, as: 'test'
                    @dev = robot.device(dev_m, as: 'device').
                        frame_transform('test_from' => 'test_to').
                        period(0.1)
                end

                it "applies the device's transformer configuration to the task's" do
                    dev.transformer { frames('test_from', 'test_to') }

                    # If the transformer configuration specified for 'dev' was not
                    # applied, we should get the error that a frame does not exist
                    syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                end

                it "raises if the source frame selected for the device does not exist" do
                    dev.transformer { frames('test_to') }

                    e = assert_raises(Transformer::InvalidConfiguration) do
                        syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                    end
                    assert_match /test_from selected as 'from' frame/, e.message
                end

                it "raises if the target frame selected for the device does not exist" do
                    dev.transformer { frames('test_from') }

                    e = assert_raises(Transformer::InvalidConfiguration) do
                        syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                    end
                    assert_match /test_to selected as 'to' frame/, e.message
                end

                it "propagates the device's frame selection to the task" do
                    dev.transformer { frames('test_from', 'test_to') }

                    task = syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                    assert_equal Hash['from' => 'test_from', 'to' => 'test_to'],
                        task.selected_frames
                end

                it "detects conflicts on the 'from' frame" do
                    dev.transformer { frames('test_from', 'test_to') }
                    req = task_m.with_arguments('test_dev' => dev).
                        use_frames('from' => 'conflict', 'to' => 'test_to')

                    e = assert_raises(FrameSelectionConflict) do
                        syskit_stub_and_deploy(req)
                    end
                    pp_e = PP.pp(e, "")
                    assert pp_e.start_with?("conflicting frames selected for from (conflict != test_from)")
                end

                it "detects conflicts on the 'to' frame" do
                    dev.transformer { frames('test_from', 'test_to') }
                    req = task_m.with_arguments('test_dev' => dev).
                        use_frames('from' => 'test_from', 'to' => 'conflict')

                    e = assert_raises(FrameSelectionConflict) do
                        syskit_stub_and_deploy(req)
                    end
                    pp_e = PP.pp(e, "")
                    assert pp_e.start_with?("conflicting frames selected for to (conflict != test_to)")
                end
            end

            describe "data producers" do
                attr_reader :dev_m, :task_m, :dev
                before do
                    @dev_m = Syskit::Device.new_submodel do
                        output_port 'data', 'double'
                    end
                    @task_m = Syskit::TaskContext.new_submodel do
                        output_port 'data', 'double'
                        transformer do
                            associate_frame_to_ports 'frame', 'data'
                            max_latency 0.1
                        end
                    end
                    task_m.driver_for dev_m, as: 'test'
                    @dev = robot.device(dev_m, as: 'device').
                        frame('test').
                        period(0.1)
                end

                it "applies the device's transformer configuration to the task's" do
                    dev.transformer { frames('test') }

                    # If the transformer configuration specified for 'dev' was not
                    # applied, we should get the error that a frame does not exist
                    syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                end

                it "raises if the source frame selected for the device does not exist" do
                    e = assert_raises(Transformer::InvalidConfiguration) do
                        syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                    end
                    assert_match /undefined frame test selected as reference frame/, e.message
                end

                it "propagates the device's frame selection to the task" do
                    dev.transformer { frames('test') }

                    task = syskit_stub_and_deploy(task_m.with_arguments('test_dev' => dev))
                    assert_equal Hash['frame' => 'test'],
                        task.selected_frames
                end

                it "detects conflicts on the frame selection" do
                    dev.transformer { frames('test') }
                    req = task_m.with_arguments('test_dev' => dev).
                        use_frames('frame' => 'conflict')

                    e = assert_raises(FrameSelectionConflict) do
                        syskit_stub_and_deploy(req)
                    end
                    pp_e = PP.pp(e, "")
                    assert pp_e.start_with?("conflicting frames selected for frame (conflict != test)")
                end
            end
        end
    end
end
