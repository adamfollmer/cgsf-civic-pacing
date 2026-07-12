# frozen_string_literal: true

require "rails_helper"

RSpec.describe "civic-pacing status endpoint", type: :request do
  fab!(:paced_category) do
    SiteSetting.cgsf_name_format_enabled = false if SiteSetting.respond_to?(:cgsf_name_format_enabled)
    Fabricate(:category, user: Discourse.system_user)
  end
  fab!(:member) { Fabricate(:user, name: nil, trust_level: 2, refresh_auto_groups: true) }
  fab!(:admin) { Fabricate(:admin, name: nil) }

  before do
    SiteSetting.cgsf_name_format_enabled = false if SiteSetting.respond_to?(:cgsf_name_format_enabled)
    SiteSetting.civic_pacing_enabled = true
    SiteSetting.civic_pacing_paced_categories = paced_category.id.to_s
    SiteSetting.civic_pacing_topic_budget = 2
  end

  it "requires login" do
    get "/civic-pacing/status.json"
    expect(response.status).to eq(403)
  end

  it "reports budgets, remaining, and paced categories" do
    sign_in(member)
    get "/civic-pacing/status.json"
    expect(response.status).to eq(200)
    json = response.parsed_body
    expect(json["actions"]["topic"]["budget"]).to eq(2)
    expect(json["actions"]["topic"]["remaining"]).to eq(2)
    expect(json["actions"]["topic"]["next_token_at"]).to be_nil
    expect(json["paced_category_ids"]).to eq([paced_category.id])
    expect(json["exempt"]).to eq(false)
  end

  it "counts spends and reports next token time when exhausted" do
    sign_in(member)
    2.times { ::CgsfCivicPacing.record!(member, "topic") }
    get "/civic-pacing/status.json"
    json = response.parsed_body
    expect(json["actions"]["topic"]["remaining"]).to eq(0)
    expect(json["actions"]["topic"]["next_token_at"]).to be_present
  end

  it "marks staff exempt" do
    sign_in(admin)
    get "/civic-pacing/status.json"
    expect(response.parsed_body["exempt"]).to eq(true)
  end
end
