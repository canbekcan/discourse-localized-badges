# frozen_string_literal: true

class SeedFoundingMemberBadge < ActiveRecord::Migration[7.0]
  def up
    # Find the badge by its exact name or initialize a new one (Idempotency check for fresh installs)
    # This ensures the migration can be re-run safely without throwing duplicate key errors
    badge = Badge.find_or_initialize_by(name: 'badges.founding_member.name')

    # Define the raw SQL query to identify the first 150 active users sorted by account creation time
    # 'id > 0' ensures system users (like the Discourse 'system' user with id: -1) are excluded
    # CURRENT_TIMESTAMP provides the exact time the database executes the query for the grant
    sql_query = <<~SQL
      SELECT id AS user_id, CURRENT_TIMESTAMP AS granted_at
      FROM users
      WHERE id > 0 AND active = true
      ORDER BY created_at ASC
      LIMIT 150
    SQL

    # Persist the badge configuration to the database
    # The update! method is used so that any validation failure instantly halts the migration with an error
    badge.update!(
      name: 'badges.founding_member.name', # Set the localized name key
      description: 'badges.founding_member.description', # Set the localized description key
      long_description: 'badges.founding_member.long_description', # Set the localized long description key
      query: sql_query, # Attach the target SQL query for the badge engine
      trigger: 0, # Badge::Trigger::None (The badge is granted via the SQL query, not by an event hook)
      auto_revoke: false, # Ensure the badge is permanent and not stripped by daily background jobs
      allow_title: true, # Allow users to select this badge as their profile title
      system: false # Mark as a custom plugin badge so Discourse core updates do not overwrite it
    )
  end

  def down
    # Provide a clean rollback path (db:rollback) by locating the exact badge and destroying it
    # Safe navigation (&) prevents NoMethodError if the badge is already missing from the database
    Badge.find_by(name: 'badges.founding_member.name')&.destroy
  end
end