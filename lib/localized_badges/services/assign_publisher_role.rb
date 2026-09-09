# frozen_string_literal: true

module LocalizedBadges
  module Services
    class AssignPublisherRole
      def initialize(user)
        @user = user
      end

      def call
        return if @user.nil? || @user.staff?
        evaluate_roles_and_badges
      end

      private

      def evaluate_roles_and_badges
        domains = SiteSetting.publisher_email_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
        groups_setting = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)
        
        user_domain = @user.email.to_s.split('@').last.to_s.downcase
        is_valid = domains.any? { |d| user_domain == d || user_domain.end_with?(".#{d}") }

        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

        if is_valid
          # KULLANICI LİSTEDEYSE: Yetkileri Ver (ID veya İsimle Grup Arama Düzeltmesi)
          groups_setting.each do |group_name_or_id|
            group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
            group.add(@user) if group && !group.users.include?(@user)
          end

          BadgeGranter.grant(publisher_badge, @user) if publisher_badge && !@user.user_badges.exists?(badge_id: publisher_badge.id)
        else
          # KULLANICI LİSTEDE DEĞİLSE: Eski Yetkileri Geri Al (Domain Silinme Durumu)
          if publisher_badge && @user.user_badges.exists?(badge_id: publisher_badge.id)
            user_badge = UserBadge.find_by(user_id: @user.id, badge_id: publisher_badge.id)
            BadgeGranter.revoke(user_badge) if user_badge
            
            groups_setting.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(@user) if group && group.users.include?(@user)
            end
            Rails.logger.info("DevOps [discourse-localized-badges]: #{@user.username} yetkisi, #{user_domain} domaini kaldirildigi icin geri alindi.")
          end
        end
      end
    end
  end
end