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
            check_and_manage('Gold Sponsor', SiteSetting.localized_badges_gold_sponsor_domains)
            check_and_manage('Silver Sponsor', SiteSetting.localized_badges_silver_sponsor_domains)
            check_and_manage('Bronze Sponsor', SiteSetting.localized_badges_bronze_sponsor_domains)
            check_and_manage('Verified Partner', SiteSetting.localized_badges_partner_domains)
          end
        end
      end

      private

      def check_and_manage(badge_name, domains_setting)
        badge = Badge.find_by(name: badge_name)
        return unless badge

        # Ayar tamamen boşsa bile return etme. Array'e çevir ki aşağıdaki 'else' bloğu çalışıp rozeti geri alabilsin.
        domain_list = domains_setting.to_s.split('|').reject(&:blank?).map(&:downcase)
        
        if domain_list.include?(@domain)
          BadgeGranter.grant(badge, @user)
        else
          # Kullanıcıda rozet varsa ve domain listesinde artık yoksa rozeti anında geri al (revoke)
          user_badge = UserBadge.find_by(user_id: @user.id, badge_id: badge.id)
          BadgeGranter.revoke(user_badge) if user_badge
        end
      end
    end
  end
end