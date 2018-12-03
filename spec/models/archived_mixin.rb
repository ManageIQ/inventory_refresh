module ArchivedMixin
  extend ActiveSupport::Concern

  included do
    scope :archived, -> { where.not(:archived_at => nil) }
    scope :active, -> { where(:archived_at => nil) }
  end

  def archived?
    !active?
  end
  alias_method :archived, :archived?

  def active?
    archived_at.nil?
  end
  alias_method :active, :active?

  def archive!
    update_attributes!(:archived_at => Time.now.utc)
  end

  def unarchive!
    update_attributes!(:archived_at => nil)
  end

  def self.archive!(ids)
    where(:id => ids).update_all(:archived_at => Time.now.utc)
  end
end
