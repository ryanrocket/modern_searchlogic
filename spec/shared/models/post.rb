class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments
  has_many :votes, as: :voteable

  def self.is_like(something)
    "whoops"
  end

  scope :published, -> do
    where(arel_table[:published_at].not_eq(nil))
  end

  scope_procedure :for_home_page, lambda { Post.published.descend_by_published_at }
  scope_procedure :published_grouped_by_user, lambda { published.group_by(&:user) }
  scope_procedure :published_for_user, lambda { |*users| published.user_id_in(users.map(&:id)) }
  scope_procedure :published_for_users, :published_for_user
  scope_procedure :active, lambda { created_at_lt(Time.zone.now) }
end
