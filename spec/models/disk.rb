require_relative 'archived_mixin'

class Disk < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :hardware
end
