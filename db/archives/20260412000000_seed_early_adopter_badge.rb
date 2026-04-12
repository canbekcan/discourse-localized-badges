# frozen_string_literal: true

class SeedEarlyAdopterBadge < ActiveRecord::Migration[7.0]
  def up
    # Önce eski isimle (e harfiyle) olanı ara
    badge = Badge.find_by(name: 'badges.early_adapter.name') 
    
    # Eğer eski isimle yoksa, yeni ismi bul veya oluştur (o harfiyle)
    badge ||= Badge.find_or_initialize_by(name: 'badges.early_adopter.name')

    sql_query = <<~SQL
      SELECT id AS user_id, CURRENT_TIMESTAMP AS granted_at
      FROM users
      WHERE id > 0 AND active = true
      ORDER BY created_at ASC
      LIMIT 200
    SQL

    badge.update!(
      name: 'badges.early_adopter.name', # İsmi 'o' harfine zorla
      description: 'badges.early_adopter.description',
      long_description: 'badges.early_adopter.long_description',
      query: sql_query,
      trigger: 0,
      auto_revoke: false,
      allow_title: true,
      system: false
    )
  end

  def down
    # Rollback durumunda yeni ismi silebiliriz
    Badge.find_by(name: 'badges.early_adopter.name')&.destroy
  end
end