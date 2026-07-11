# frozen_string_literal: true

class CreateCivicPacingEvents < ActiveRecord::Migration[7.2]
  def change
    # The content-free ledger: records that a member acted, never what on.
    create_table :civic_pacing_events do |t|
      t.integer :user_id, null: false
      t.string :action, null: false, limit: 20
      t.datetime :created_at, null: false
    end

    add_index :civic_pacing_events, %i[user_id action created_at],
              name: "idx_civic_pacing_events_lookup"
  end
end
