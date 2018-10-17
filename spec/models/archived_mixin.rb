module ArchivedMixin
  extend ActiveSupport::Concern

  included do
    scope :archived, -> { where.not(:archived_on => nil) }
    scope :active, -> { where(:archived_on => nil) }
  end

  def archived?
    !active?
  end
  alias_method :archived, :archived?

  def active?
    archived_on.nil?
  end
  alias_method :active, :active?

  def archive!
    update_attributes!(:archived_on => Time.now.utc)
  end

  def unarchive!
    update_attributes!(:archived_on => nil)
  end

  def self.archive!(ids)
    where(:id => ids).update_all(:archived_on => Time.now.utc)
  end
end
