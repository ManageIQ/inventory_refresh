FactoryBot.define do
  factory :host do
    sequence(:name)     { |n| "host_#{seq_padded_for_sorting(n)}" }
    sequence(:hostname) { |n| "host-#{seq_padded_for_sorting(n)}" }
    vmm_vendor          { "vmware" }
    ipaddress           { "127.0.0.1" }
    user_assigned_os    { "linux_generic" }
    power_state         { "on" }
  end
end
