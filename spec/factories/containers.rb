FactoryBot.define do
  factory :container do
    sequence(:name) { |n| "container_#{seq_padded_for_sorting(n)}" }
  end
end
