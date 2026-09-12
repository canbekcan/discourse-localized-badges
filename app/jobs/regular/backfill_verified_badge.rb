# frozen_string_literal: true

module Jobs
  class BackfillVerifiedBadge < ::Jobs::Base
    def execute(args)
      badge = Badge.find_by(name: 'Verified') || Badge.find_by(name: 'badges.verified.name')
      return unless badge

      BadgeGranter.backfill(badge)

      Rails.logger.info(
        "DevOps [discourse-localized-badges]: Verified rozeti backfill islemi tamamlandi. " \
        "Tum kullanicilar yeni domain listesine gore yeniden taranarak rozet verildi/geri alindi."
      )
    end
  end
end
