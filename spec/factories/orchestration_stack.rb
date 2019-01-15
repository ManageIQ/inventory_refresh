FactoryBot.define do
  factory :orchestration_stack do
    ems_ref "1"
  end

  factory :orchestration_stack_cloud, :parent => :orchestration_stack, :class => "ManageIQ::Providers::CloudManager::OrchestrationStack"
end
