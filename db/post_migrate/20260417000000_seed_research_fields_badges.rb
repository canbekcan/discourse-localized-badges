# frozen_string_literal: true

class SeedResearchFieldsBadges < ActiveRecord::Migration[7.0]
  def up
    # 1. YENİ ROZET GRUBUNU (RESEARCH FIELDS) OLUŞTUR
    grouping = BadgeGrouping.find_or_initialize_by(name: 'badge_groupings.research_fields.name')
    grouping.update!(
      description: 'badge_groupings.research_fields.description',
      position: BadgeGrouping.maximum(:position).to_i + 1, # Listede en sona ekler
      system: false
    )

    # 2. SOCIAL SCIENTIST ROZETİ (Gümüş)
    social_sql = <<~SQL
      SELECT gu.user_id, CURRENT_TIMESTAMP AS granted_at
      FROM group_users gu
      JOIN groups g ON g.id = gu.group_id
        -- DİKKAT: Buradaki 'SocialScience' grubun sistem (URL) adıdır.
      WHERE g.name = 'SocialScience' 
        AND (:backfill OR gu.user_id IN (:user_ids))
    SQL

    social_badge = Badge.find_or_initialize_by(name: 'badges.social_scientist.name')
    social_badge.update!(
      description: 'badges.social_scientist.description',
      long_description: 'badges.social_scientist.long_description',
      badge_type_id: 2,               # 2: Gümüş (Silver)
      badge_grouping_id: grouping.id, # Yeni oluşturduğumuz grubun ID'sini atar
      query: social_sql,
      trigger: 0,                     # Gece (Günlük) Kontrol
      auto_revoke: true,              # Gruptan ayrılırsa rozet otomatik geri alınır
      allow_title: true,
      system: false
    )

    # 3. SCIENTIST ROZETİ (Gümüş)
    scientist_sql = <<~SQL
      SELECT gu.user_id, CURRENT_TIMESTAMP AS granted_at
      FROM group_users gu
      JOIN groups g ON g.id = gu.group_id
      -- DİKKAT: Buradaki 'Science' grubun sistem (URL) adıdır.
      WHERE g.name = 'Science'
        AND (:backfill OR gu.user_id IN (:user_ids))
    SQL

    scientist_badge = Badge.find_or_initialize_by(name: 'badges.scientist.name')
    scientist_badge.update!(
      description: 'badges.scientist.description',
      long_description: 'badges.scientist.long_description',
      badge_type_id: 2,               # 2: Gümüş
      badge_grouping_id: grouping.id,
      query: scientist_sql,
      trigger: 0,
      auto_revoke: true,
      allow_title: true,
      system: false
    )
  end

  def down
    # Eklenti kaldırılırsa temizlik işlemleri
    Badge.find_by(name: 'badges.social_scientist.name')&.destroy
    Badge.find_by(name: 'badges.scientist.name')&.destroy
    BadgeGrouping.find_by(name: 'badge_groupings.research_fields.name')&.destroy
  end
end