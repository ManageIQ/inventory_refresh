def seq_padded_for_sorting(n)
  n.to_s.rjust(13, '0') # pad to 13 for max region size
end

require "factory_girl"
FactoryGirl.find_definitions
