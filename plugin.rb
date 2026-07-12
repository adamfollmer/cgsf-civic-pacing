# frozen_string_literal: true

# name: cgsf-civic-pacing
# about: Token-budget pacing for designated civic categories — equal rolling budgets, no reputation
# version: 0.1.0
# authors: Adam F.
# url: https://github.com/adamfollmer/cgsf-civic-pacing
# required_version: 2.7.0

enabled_site_setting :civic_pacing_enabled

register_asset "stylesheets/civic-pacing.scss"

after_initialize do
  class ::CivicPacingEvent < ::ActiveRecord::Base
    self.table_name = "civic_pacing_events"
  end

  module ::CgsfCivicPacing
    # The ledger records THAT a member acted, never WHAT on — no content references.
    ACTIONS = {
      "topic" => %i[civic_pacing_topic_budget civic_pacing_topic_window_days],
      "reply" => %i[civic_pacing_reply_budget civic_pacing_reply_window_days],
      "like"  => %i[civic_pacing_like_budget civic_pacing_like_window_days],
    }

    def self.paced_category?(category_id)
      return false if category_id.blank?
      SiteSetting.civic_pacing_paced_categories.split("|").map(&:to_i).include?(category_id)
    end

    # Equal budgets for every member; visible-role staff bypass; bots exempt.
    def self.exempt?(user)
      user.nil? || user.id < 1 || user.staff?
    end

    def self.budget(action) = SiteSetting.get(ACTIONS[action][0])
    def self.window(action) = SiteSetting.get(ACTIONS[action][1]).days

    def self.in_window(user, action)
      CivicPacingEvent
        .where(user_id: user.id, action: action)
        .where("created_at > ?", window(action).ago)
    end

    # Token state is COMPUTED at read time from the ledger against current
    # settings — never stored — so budget retunes are retroactively safe.
    def self.allowed?(user, action)
      in_window(user, action).count < budget(action)
    end

    def self.next_token_at(user, action)
      oldest = in_window(user, action).order(:created_at).first
      oldest ? oldest.created_at + window(action) : Time.zone.now
    end

    def self.record!(user, action)
      CivicPacingEvent.create!(user_id: user.id, action: action)
    end

    def self.deny!(record, user, action)
      hours = ((next_token_at(user, action) - Time.zone.now) / 1.hour).ceil.clamp(1, 24 * 365)
      record.errors.add(
        :base,
        I18n.t("civic_pacing.limit_reached.#{action}", count: budget(action), hours: hours),
      )
    end
  end

  # --- Member-facing token status (the June design's my_cooldowns, reborn) ---

  class ::CgsfCivicPacing::StatusController < ::ApplicationController
    requires_plugin "cgsf-civic-pacing"
    before_action :ensure_logged_in

    def show
      actions = ::CgsfCivicPacing::ACTIONS.keys.to_h do |action|
        budget = ::CgsfCivicPacing.budget(action)
        used = ::CgsfCivicPacing.in_window(current_user, action).count
        remaining = [budget - used, 0].max
        [
          action,
          {
            budget: budget,
            remaining: remaining,
            window_days: SiteSetting.get(::CgsfCivicPacing::ACTIONS[action][1]),
            next_token_at:
              remaining.zero? ? ::CgsfCivicPacing.next_token_at(current_user, action).iso8601 : nil,
          },
        ]
      end

      render json: {
        actions: actions,
        paced_category_ids: SiteSetting.civic_pacing_paced_categories.split("|").map(&:to_i),
        exempt: ::CgsfCivicPacing.exempt?(current_user),
      }
    end
  end

  Discourse::Application.routes.append do
    get "/civic-pacing/status" => "cgsf_civic_pacing/status#show"
  end

  # --- Guards (validation-time) ---

  add_model_callback(:topic, :validate) do
    next unless SiteSetting.civic_pacing_enabled
    next unless new_record?
    next unless ::CgsfCivicPacing.paced_category?(category_id)
    next if ::CgsfCivicPacing.exempt?(user)

    ::CgsfCivicPacing.deny!(self, user, "topic") unless ::CgsfCivicPacing.allowed?(user, "topic")
  end

  add_model_callback(:post, :validate) do
    next unless SiteSetting.civic_pacing_enabled
    next unless new_record?
    next unless post_type == Post.types[:regular]
    next unless topic && topic.highest_post_number.to_i >= 1 # replies only; the topic guard covers first posts
    next unless ::CgsfCivicPacing.paced_category?(topic.category_id)
    next if ::CgsfCivicPacing.exempt?(user)

    ::CgsfCivicPacing.deny!(self, user, "reply") unless ::CgsfCivicPacing.allowed?(user, "reply")
  end

  add_model_callback(:post_action, :validate) do
    next unless SiteSetting.civic_pacing_enabled
    next unless new_record?
    next unless post_action_type_id == PostActionType.types[:like]
    next unless ::CgsfCivicPacing.paced_category?(post&.topic&.category_id)
    next if ::CgsfCivicPacing.exempt?(user)

    ::CgsfCivicPacing.deny!(self, user, "like") unless ::CgsfCivicPacing.allowed?(user, "like")
  end

  # --- Ledger writes (after the action really happened) ---

  on(:topic_created) do |topic, _opts, user|
    next unless SiteSetting.civic_pacing_enabled
    next unless ::CgsfCivicPacing.paced_category?(topic.category_id)
    next if ::CgsfCivicPacing.exempt?(user)
    ::CgsfCivicPacing.record!(user, "topic")
  end

  on(:post_created) do |post, _opts, user|
    next unless SiteSetting.civic_pacing_enabled
    next if post.is_first_post?
    next unless post.post_type == Post.types[:regular]
    next unless ::CgsfCivicPacing.paced_category?(post.topic&.category_id)
    next if ::CgsfCivicPacing.exempt?(user)
    ::CgsfCivicPacing.record!(user, "reply")
  end

  on(:like_created) do |post_action|
    next unless SiteSetting.civic_pacing_enabled
    user = post_action.user
    next unless ::CgsfCivicPacing.paced_category?(post_action.post&.topic&.category_id)
    next if ::CgsfCivicPacing.exempt?(user)
    ::CgsfCivicPacing.record!(user, "like")
  end
end
