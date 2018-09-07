FactoryGirl.define do
  factory :flavor do
    sequence(:name) { |n| "flavor_#{seq_padded_for_sorting(n)}" }
  end

  factory(:flavor_cloud, :class => "ManageIQ::Providers::CloudManager::Flavor", :parent => :flavor)
end
