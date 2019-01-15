FactoryBot.define do
  factory :availability_zone do
    sequence(:name) { |n| "availability_zone_#{seq_padded_for_sorting(n)}" }
  end
end
