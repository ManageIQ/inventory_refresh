FactoryGirl.define do
  factory :vm_or_template do
    sequence(:name)    { |n| "vm_#{seq_padded_for_sorting(n)}" }
    location           "unknown"
    uid_ems            { SecureRandom.uuid }
    sequence(:ems_ref) { |n| "vm-#{seq_padded_for_sorting(n)}" }
    vendor             "unknown"
    template           false
    raw_power_state    "running"
  end

  factory :template, :class => "MiqTemplate", :parent => :vm_or_template do
    sequence(:name) { |n| "template_#{seq_padded_for_sorting(n)}" }
    template        true
    raw_power_state "never"
  end

  factory(:vm,           :class => "Vm",               :parent => :vm_or_template)
  factory(:vm_cloud,     :class => "ManageIQ::Providers::CloudManager::Vm", :parent => :vm) { cloud true }
  factory(:miq_template, :parent => :template)
end
