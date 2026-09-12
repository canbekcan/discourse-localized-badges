# frozen_string_literal: true

# ⚠️ GEÇİCİ DOSYA — Eski plugin versiyonundan Sidekiq kuyruğunda kalan
# "evaluate_retroactive_publisher_badges" job'larının hatasız tamamlanması için gereklidir.
# Kuyruk tamamen temizlendikten sonra bu dosya ve plugin.rb'deki require_relative satırı silinebilir.

module Jobs
  class EvaluateRetroactivePublisherBadges < ::Jobs::Base
    def execute(args)
      Rails.logger.info(
        "DevOps [discourse-localized-badges]: Eski 'evaluate_retroactive_publisher_badges' job'i calisti ve atlanidi. " \
        "Bu job eski bir plugin versiyonundan kalmistir."
      )
    end
  end
end
