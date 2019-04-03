require_relative "../test_builder"

class TestBuilder::CloudManager < TestBuilder
  def flavors
    add_common_default_values
  end

  def orchestration_stacks
    add_common_default_values
  end

  def orchestration_stacks_resources
    add_properties(
      :model_class => ::OrchestrationStackResource,
    )
  end
end
