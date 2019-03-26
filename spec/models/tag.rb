class Tag < ActiveRecord::Base
  has_many :container_group_tags
  has_many :container_groups, :through => :container_group_tags
end
