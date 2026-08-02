# frozen_string_literal: true

class SeedVerifiedBadge < ActiveRecord::Migration[7.0]
  def up
    badge = Badge.find_by(name: 'Verified') || Badge.find_by(name: 'badges.verified.name')
    badge ||= Badge.new(name: 'Verified')

    # AKADEMİK GÜVENLİK FİLTRESİ EKLELENMİŞ SQL
    sql_query = <<~SQL
      WITH allowed_domains AS (
        SELECT NULLIF(TRIM(unnest(string_to_array(value, '|'))), '') AS domain
        FROM site_settings 
        WHERE name = 'verified_academic_domains' 
          AND value IS NOT NULL 
          AND value != ''
      ),
      valid_domains AS (
        SELECT domain FROM allowed_domains WHERE domain IS NOT NULL
      )
      SELECT DISTINCT
        u.id AS user_id, 
        CURRENT_TIMESTAMP AS granted_at
      FROM users u
      JOIN user_emails ue ON ue.user_id = u.id AND ue."primary" = true
      JOIN valid_domains ad ON (
        -- DURUM 1: Domain birebir eşleşiyorsa (Örn: bekcan.com)
        split_part(ue.email, '@', 2) ILIKE ad.domain OR 
        -- DURUM 2: Domain girdiğimiz uzantıyla NOKTALI olarak bitiyorsa (Örn: .edu.tr ile biten universite.edu.tr)
        split_part(ue.email, '@', 2) ILIKE '%.' || ad.domain
      )
      WHERE u.active = true
        AND u.suspended_at IS NULL
        AND (:backfill OR u.id IN (:user_ids))
    SQL

    badge.update!(
      name: 'Verified',
      description: 'badges.verified.description',
      long_description: 'badges.verified.long_description',
      badge_type_id: 3,          
      badge_grouping_id: 1,      
      query: sql_query,
      trigger: 4,                
      auto_revoke: true,         
      allow_title: true,         
      system: false              
    )
  end

  def down
    Badge.find_by(name: 'Verified')&.destroy
    Badge.find_by(name: 'badges.verified.name')&.destroy
  end
end