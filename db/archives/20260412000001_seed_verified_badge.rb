# frozen_string_literal: true

class SeedVerifiedBadge < ActiveRecord::Migration[7.0]
  def up
    # 1. Önce admin panelinden elle açılmış olan "Verified" rozetini bul
    badge = Badge.find_by(name: 'Verified')

    # 2. Eğer manuel rozet yoksa (sıfırdan kurulumsa), çeviri anahtarıyla bul veya oluştur
    badge ||= Badge.find_or_initialize_by(name: 'badges.verified.name')

    # SQL Sorgunuz
    sql_query = <<~SQL
      WITH allowed_domains AS (
        SELECT unnest(string_to_array(value, '|')) AS domain
        FROM site_settings 
        WHERE name = 'allowed_email_domains' 
          AND value IS NOT NULL 
          AND value != ''
      )
      SELECT DISTINCT
        u.id AS user_id, 
        CURRENT_TIMESTAMP AS granted_at
      FROM users u
      JOIN user_emails ue ON ue.user_id = u.id
      JOIN allowed_domains ad ON (
        ue.email ILIKE '%@' || trim(ad.domain) OR 
        ue.email ILIKE '%.' || trim(ad.domain)
      )
      WHERE ue."primary" = true
        AND u.active = true
        AND u.suspended_at IS NULL
        AND (:backfill OR u.id IN (:user_ids))
    SQL

    # Rozet özelliklerini ve SQL sorgusunu veritabanına kaydet
    badge.update!(
      description: 'badges.verified.description',
      long_description: 'badges.verified.long_description',
      badge_type_id: 3,          # 1: Altın, 2: Gümüş, 3: Bronz. (Doğrulama rozetleri genelde bronz olur, isterseniz değiştirebilirsiniz)
      badge_grouping_id: 1,      # Rozet grubu
      query: sql_query,
      trigger: 0,                # 0 = Update Daily (Sorgu her gece veya kullanıcı profil güncellediğinde çalışır)
      auto_revoke: true,         # KRİTİK: Kullanıcı emailini farklı bir domaine değiştirirse rozet geri alınır.
      allow_title: true,         # Kullanıcı bunu isminin yanında unvan olarak kullanabilsin.
      system: false              # Admin arayüzünde görünmesi ve üzerinde manuel değişiklik yapılabilmesi için.
    )
  end

  def down
    # Eklenti veya migrasyon geri alınırsa rozeti temizle
    Badge.find_by(name: 'badges.verified.name')&.destroy
  end
end