# frozen_string_literal: true

module LocalizedBadges
  module Services
    class AssignSponsorBadges
      def initialize(user)
        @user = user
        @domain = user.email&.split('@')&.last&.downcase
      end

      def call
        return if @domain.blank? || !@user.active?

        # Eşzamanlı işlemlerde veritabanı çakışmalarını önlemek için kilit (lock)
        DistributedMutex.synchronize("assign_sponsor_badge_#{@user.id}") do
          ActiveRecord::Base.transaction do
            check_and_grant('Gold Sponsor', SiteSetting.localized_badges_gold_sponsor_domains)
            check_and_grant('Silver Sponsor', SiteSetting.localized_badges_silver_sponsor_domains)
            check_and_grant('Bronze Sponsor', SiteSetting.localized_badges_bronze_sponsor_domains)
            check_and_grant('Verified Partner', SiteSetting.localized_badges_partner_domains)
          end
        end
      end

      private

      def check_and_grant(badge_name, domains_setting)
        return if domains_setting.blank?

        # Discourse 'type: list' ayarlarını Ruby tarafında pipe ('|') ile ayrılmış string olarak döndürür
        domain_list = domains_setting.is_a?(String) ? domains_setting.split('|').map(&:downcase) : []
        
        if domain_list.include?(@domain)
          badge = Badge.find_by(name: badge_name)
          BadgeGranter.grant(badge, @user) if badge
        end
      end
    end
  end
end