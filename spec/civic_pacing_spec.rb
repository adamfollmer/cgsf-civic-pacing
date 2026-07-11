# frozen_string_literal: true

require "rails_helper"

RSpec.describe "cgsf-civic-pacing" do
  # cgsf-name-format (if co-loaded) rejects fabricated users' random full names; it's
  # not under test here. fab! prefabricates before `before` hooks run, so every
  # fabricated record below carries an explicit name-safe user, and the first fab!
  # plus the before hook disable the setting for anything created later.
  fab!(:paced_category) do
    SiteSetting.cgsf_name_format_enabled = false if SiteSetting.respond_to?(:cgsf_name_format_enabled)
    Fabricate(:category, user: Discourse.system_user)
  end
  fab!(:free_category) { Fabricate(:category, user: Discourse.system_user) }
  fab!(:member) { Fabricate(:user, name: nil, trust_level: 2, refresh_auto_groups: true) }
  fab!(:poster) { Fabricate(:user, name: nil, trust_level: 2, refresh_auto_groups: true) }
  fab!(:admin) { Fabricate(:admin, name: nil) }

  before do
    SiteSetting.cgsf_name_format_enabled = false if SiteSetting.respond_to?(:cgsf_name_format_enabled)
    SiteSetting.civic_pacing_enabled = true
    SiteSetting.civic_pacing_paced_categories = paced_category.id.to_s
    SiteSetting.civic_pacing_topic_budget = 1
    SiteSetting.civic_pacing_reply_budget = 2
    SiteSetting.civic_pacing_like_budget = 2
  end

  # Returns the PostCreator so callers can inspect .errors on success AND failure.
  def make_topic(user, category, suffix = SecureRandom.hex(4))
    creator = PostCreator.new(
      user,
      title: "A civic topic about drainage #{suffix}",
      raw: "Words about the issue, at reasonable length for a post body.",
      category: category.id,
    )
    creator.create
    creator
  end

  def make_reply(user, topic)
    creator = PostCreator.new(
      user,
      topic_id: topic.id,
      raw: "A reply with enough words to pass validation #{SecureRandom.hex(4)}.",
    )
    creator.create
    creator
  end

  describe "topic budget" do
    it "allows up to the budget, then blocks with a friendly error" do
      expect(make_topic(member, paced_category).errors).to be_blank

      second = make_topic(member, paced_category)
      expect(second.errors.full_messages.join).to include("new-topic token")
    end

    it "does not spend tokens in unpaced categories" do
      make_topic(member, paced_category)
      expect(make_topic(member, free_category).errors).to be_blank
    end

    it "returns the token when the spend ages out of the rolling window" do
      make_topic(member, paced_category)
      freeze_time(SiteSetting.civic_pacing_topic_window_days.days.from_now + 1.minute)
      expect(make_topic(member, paced_category).errors).to be_blank
    end

    it "exempts staff" do
      2.times { |i| expect(make_topic(admin, paced_category, "n#{i}").errors).to be_blank }
    end
  end

  describe "reply budget" do
    fab!(:topic) { Fabricate(:topic, category: paced_category, user: poster) }
    fab!(:op) { Fabricate(:post, topic: topic, user: poster) }

    it "allows up to the budget, then blocks" do
      2.times { expect(make_reply(member, topic).errors).to be_blank }
      third = make_reply(member, topic)
      expect(third.errors.full_messages.join).to include("reply token")
    end

    it "creating a paced topic does not consume reply tokens" do
      make_topic(member, paced_category)
      2.times { expect(make_reply(member, topic).errors).to be_blank }
    end
  end

  describe "like budget" do
    fab!(:topic) { Fabricate(:topic, category: paced_category, user: poster) }
    fab!(:posts) { 3.times.map { Fabricate(:post, topic: topic, user: poster) } }

    it "allows up to the budget, then blocks" do
      expect(PostActionCreator.like(member, posts[0]).success).to eq(true)
      expect(PostActionCreator.like(member, posts[1]).success).to eq(true)
      expect(PostActionCreator.like(member, posts[2]).success).to eq(false)
    end

    it "likes in unpaced categories are unlimited" do
      free_topic = Fabricate(:topic, category: free_category, user: poster)
      free_posts = 3.times.map { Fabricate(:post, topic: free_topic, user: poster) }
      free_posts.each { |p| expect(PostActionCreator.like(member, p).success).to eq(true) }
    end
  end

  describe "kill switch" do
    it "does nothing when disabled" do
      SiteSetting.civic_pacing_enabled = false
      2.times { |i| expect(make_topic(member, paced_category, "k#{i}").errors).to be_blank }
    end
  end

  describe "the ledger" do
    it "records only user, action, and time — no content references" do
      make_topic(member, paced_category)
      event = CivicPacingEvent.last
      expect(event.user_id).to eq(member.id)
      expect(event.action).to eq("topic")
      expect(event.attributes.keys.sort).to eq(%w[action created_at id user_id])
    end

    it "budget retunes apply retroactively (computed at read time)" do
      make_topic(member, paced_category)
      expect(make_topic(member, paced_category).errors).to be_present

      SiteSetting.civic_pacing_topic_budget = 2
      expect(make_topic(member, paced_category).errors).to be_blank
    end
  end
end
