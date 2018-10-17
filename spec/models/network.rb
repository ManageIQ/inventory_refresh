require_relative 'archived_mixin'

class Network < ActiveRecord::Base
  include ArchivedMixin

  belongs_to :hardware
end
