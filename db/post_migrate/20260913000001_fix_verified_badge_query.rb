# frozen_string_literal: true

class FixVerifiedBadgeQuery < ActiveRecord::Migration[7.0]
  def up
    badge = Badge.find_by(name: 'Verified') || Badge.find_by(name: 'badges.verified.name')
    return unless badge

    # Düzeltilmiş SQL: user_emails tablosunda "confirmed_at" sütunu yoktur.
    # Discourse'da bir user_emails satırı zaten doğrulanmış bir e-posta anlamına gelir;
    # doğrulama durumu email_tokens tablosu üzerinden takip edilir.
    # Eski sorgu: ... AND ue.confirmed_at IS NOT NULL (hatalı)
    # Yeni sorgu: Bu koşul tamamen kaldırıldı (gereksiz ve geçersiz).
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

    badge.update!(query: sql_query)

    Rails.logger.info(
      "DevOps [discourse-localized-badges]: Verified rozeti SQL sorgusu duzeltildi. " \
      "Gecersiz 'ue.confirmed_at' kosulu kaldirildi."
    )
  end

  def down
    # Geri alma işlemi gerekmiyor — eski hatalı sorguya dönmek istenilmeyeceği için.
  end
end
