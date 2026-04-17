# frozen_string_literal: true

class SeedFoundingMemberBadge < ActiveRecord::Migration[7.0]
  def up
    # Eski 'early_adopter' rozetini bul ve 'founding_member' olarak güncelle
    badge = Badge.find_by(name: 'badges.early_adopter.name') 
    badge ||= Badge.find_or_initialize_by(name: 'badges.founding_member.name')

    sql_query = <<~SQL
      SELECT id AS user_id, CURRENT_TIMESTAMP AS granted_at
      FROM users
      WHERE id > 0 AND active = true
      ORDER BY created_at ASC
      LIMIT 200
    SQL

    badge.update!(
      name: 'badges.founding_member.name', 
      description: 'badges.founding_member.description',
      long_description: 'badges.founding_member.long_description',
      query: sql_query,
      trigger: 0,
      auto_revoke: false,
      allow_title: true,
      system: false
    )
  end

  def down
    Badge.find_by(name: 'badges.founding_member.name')&.destroy
  end
end