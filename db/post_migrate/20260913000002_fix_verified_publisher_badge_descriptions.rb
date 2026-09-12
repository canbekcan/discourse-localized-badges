# frozen_string_literal: true

class FixVerifiedPublisherBadgeDescriptions < ActiveRecord::Migration[7.0]
  def up
    badge = Badge.find_by(name: 'Verified Publisher')
    return unless badge

    # Düzeltme: Önceki migrasyon dosyasında b[:key] tanımsızdı (nil),
    # bu yüzden description ve long_description "badges..description" ve
    # "badges..long_description" olarak kaydedilmişti. Doğru i18n anahtarları
    # ile güncelliyoruz.
    badge.update!(
      description: 'badges.verified_publisher.description',
      long_description: 'badges.verified_publisher.long_description'
    )

    Rails.logger.info(
      "DevOps [discourse-localized-badges]: Verified Publisher rozeti " \
      "description ve long_description alanlari duzeltildi."
    )
  end

  def down
    # Geri alma işlemi gerekmiyor.
  end
end
