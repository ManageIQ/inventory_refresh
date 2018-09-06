FactoryGirl.define do
  factory :event_stream
  factory :ems_event, :parent => :event_stream
end
