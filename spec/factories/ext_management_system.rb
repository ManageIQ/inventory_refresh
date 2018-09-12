FactoryGirl.define do
  factory :ext_management_system do
    sequence(:name)      { |n| "ems_#{seq_padded_for_sorting(n)}" }
    guid                 { SecureRandom.uuid }
  end

  # Intermediate classes

  factory :ems_physical_infra,
          :aliases => ["physical_infra_manager"],
          :class   => "PhysicalInfraManager",
          :parent  => :ext_management_system

  factory :ems_cloud,
          :aliases => ["cloud_manager"],
          :class   => "ManageIQ::Providers::CloudManager",
          :parent  => :ext_management_system

  factory :ems_container,
          :aliases => ["container_manager"],
          :class   => "ManageIQ::Providers::ContainerManager",
          :parent  => :ext_management_system

  factory :ems_network,
          :aliases => ["network_manager"],
          :class   => "ManageIQ::Providers::NetworkManager",
          :parent  => :ext_management_system
end
