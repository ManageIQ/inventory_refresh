require_relative "../test_builder"

class TestBuilder::CloudManager < TestBuilder
  def flavors
    add_common_default_values
  end

  def key_pairs
    add_properties(
      :model_class => ManageIQ::Providers::CloudManager::AuthKeyPair,
      :manager_ref => %i(name)
    )
    add_default_values(
      :resource_id   => ->(persister) { persister.manager.id },
      :resource_type => ->(persister) { persister.manager.class.base_class }
    )
  end

  def orchestration_stacks
    add_common_default_values
  end

  def orchestration_stacks_resources
    add_properties(
      :model_class                  => ::OrchestrationStackResource,
      :parent_inventory_collections => %i(orchestration_stacks)
    )
  end
end
