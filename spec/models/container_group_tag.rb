class ContainerGroupTag < ActiveRecord::Base
  belongs_to :container_group
  belongs_to :tag
end
