# frozen_string_literal: true

# Migration class to seed the Research Fields badge grouping and associated badges.
# Inherits from ActiveRecord::Migration[7.0] to comply with Rails 7 database migration standards.
class SeedResearchFieldsBadges < ActiveRecord::Migration[7.0]
  
  # The 'up' method defines the forward database changes to apply during db:migrate.
  def up
    # ====================================================================
    # 1. CREATE BADGE GROUPING (RESEARCH FIELDS)
    # ====================================================================
    
    # Look up the custom badge grouping by its translation key, or initialize a new object if it doesn't exist.
    # This ensures idempotency on fresh installations or re-runs without throwing duplicate key errors.
    grouping = BadgeGrouping.find_or_initialize_by(name: 'badge_groupings.research_fields.name')
    
    # Persist the grouping to the database with the required attributes.
    # Uses update! to raise an ActiveRecord::RecordInvalid exception and halt the migration if validations fail.
    grouping.update!(
      # Assign the localized description key for the grouping.
      description: 'badge_groupings.research_fields.description',
      # Dynamically set the display position to be at the very end of the existing groupings list.
      position: BadgeGrouping.maximum(:position).to_i + 1
    )

    # ====================================================================
    # 2. SEED SOCIAL SCIENTIST BADGE (SILVER)
    # ====================================================================
    
    # Define the raw SQL query required by the Discourse Badge Engine to automatically grant the badge.
    # It joins the group_users and groups tables to find active members of the target group.
    social_sql = <<~SQL
      SELECT gu.user_id, CURRENT_TIMESTAMP AS granted_at
      FROM group_users gu
      JOIN groups g ON g.id = gu.group_id
      -- Ensure the group name exactly matches the system URL slug for 'socialscience'.
      WHERE g.name = 'socialscience' 
        -- Allow Discourse background jobs to filter by specific users or perform a full system backfill.
        AND (:backfill OR gu.user_id IN (:user_ids))
    SQL

    # Find or initialize the Social Scientist badge by its exact translation key to prevent duplicates.
    social_badge = Badge.find_or_initialize_by(name: 'badges.social_scientist.name')
    
    # Save the badge configuration securely to the database.
    social_badge.update!(
      description: 'badges.social_scientist.description', # Localized description key from server.en.yml
      long_description: 'badges.social_scientist.long_description', # Localized long description key
      badge_type_id: 2, # Set badge type to 2, which natively corresponds to Silver (Gümüş)
      badge_grouping_id: grouping.id, # Link this badge to the newly created Research Fields grouping ID
      query: social_sql, # Attach the raw SQL query for automatic assignment via Badge Engine
      trigger: 0, # Set trigger to Badge::Trigger::None (0) as it relies on the daily background job or group changes
      auto_revoke: true, # Automatically remove the badge from the user if they leave the 'socialscience' group
      allow_title: true, # Permit users to display this badge name as their public profile title
      system: false # Explicitly mark as a custom plugin badge so core updates do not override it
    )

    # ====================================================================
    # 3. SEED SCIENTIST BADGE (SILVER)
    # ====================================================================
    
    # Define the SQL query to grant the badge to members of the 'science' group.
    scientist_sql = <<~SQL
      SELECT gu.user_id, CURRENT_TIMESTAMP AS granted_at
      FROM group_users gu
      JOIN groups g ON g.id = gu.group_id
      -- Ensure the group name exactly matches the system URL slug for 'science'.
      WHERE g.name = 'science'
        -- Support targeted user updates and full system backfills injected by the Badge Engine.
        AND (:backfill OR gu.user_id IN (:user_ids))
    SQL

    # Find or initialize the Scientist badge by its exact translation key.
    scientist_badge = Badge.find_or_initialize_by(name: 'badges.scientist.name')
    
    # Save the Scientist badge configuration to the database.
    scientist_badge.update!(
      description: 'badges.scientist.description', # Localized description key
      long_description: 'badges.scientist.long_description', # Localized long description key
      badge_type_id: 2, # Set badge type to 2 (Silver)
      badge_grouping_id: grouping.id, # Link to the dynamic ID of the Research Fields grouping
      query: scientist_sql, # Attach the Scientist SQL query
      trigger: 0, # Badge::Trigger::None (0)
      auto_revoke: true, # Automatically revoke if the user leaves the target group
      allow_title: true, # Allow usage as a user title
      system: false # Mark as a custom plugin badge
    )
  end

  # The 'down' method defines how to revert the changes if the migration is rolled back (db:rollback).
  def down
    # Find and destroy the Social Scientist badge if it exists in the database. 
    # The safe navigation operator (&) prevents NoMethodError if the record is already deleted.
    Badge.find_by(name: 'badges.social_scientist.name')&.destroy
    
    # Find and destroy the Scientist badge safely.
    Badge.find_by(name: 'badges.scientist.name')&.destroy
    
    # Find and destroy the custom Research Fields grouping safely.
    BadgeGrouping.find_by(name: 'badge_groupings.research_fields.name')&.destroy
  end
end