class ExpireDraftPlansJob < ApplicationJob
  queue_as :default

  def perform
    Plan.draft.where("created_at < ?", 2.hours.ago).update_all(status: Plan.statuses[:expired], updated_at: Time.current)
  end
end

