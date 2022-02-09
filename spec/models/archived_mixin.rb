module ArchivedMixin
  extend ActiveSupport::Concern

  included do
    scope :archived, -> { where.not(:archived_at => nil) }
    scope :active, -> { where(:archived_at => nil) }
  end

  def archived?
    !active?
  end
  alias archived archived?

  def active?
    archived_at.nil?
  end
  alias active active?

  def archive!
    update!(:archived_at => Time.now.utc)
  end

  def unarchive!
    update!(:archived_at => nil)
  end

  def self.archive!(ids)
    where(:id => ids).update_all(:archived_at => Time.now.utc)
  end
end
