FactoryGirl.define do
  factory :nested_container do
    sequence(:name) { |n| "nested_container_#{seq_padded_for_sorting(n)}" }
  end
end
