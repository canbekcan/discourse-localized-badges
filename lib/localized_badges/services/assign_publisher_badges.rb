# frozen_string_literal: true

module LocalizedBadges
  module Services
    class AssignPublisherBadges
      def initialize(user)
        @user = user
        @domain = user.email&.split('@')&.last&.downcase
      end

      def call
        return if @domain.blank? || !@user.active?

        DistributedMutex.synchronize("assign_publisher_badge_#{@user.id}") do
          ActiveRecord::Base.transaction do
            check_and_manage(
              'Verified Publisher', 
              SiteSetting.localized_badges_publisher_domains, 
              SiteSetting.publisher_target_groups
            )
          end
        end
      end

      private

      def check_and_manage(badge_name, domains_setting, groups_setting)
        badge = Badge.find_by(name: badge_name)
        return unless badge

        domain_list = domains_setting.to_s.split('|').reject(&:blank?).map(&:downcase)
        target_groups = groups_setting.to_s.split('|').reject(&:blank?)
        
        if domain_list.include?(@domain)
          BadgeGranter.grant(badge, @user)

          target_groups.each do |group_name_or_id|
            group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
            group.add(@user) if group && !group.users.include?(@user)
          end
        else
          # Rozeti geri al
          user_badge = UserBadge.find_by(user_id: @user.id, badge_id: badge.id)
          BadgeGranter.revoke(user_badge) if user_badge

          # İlgili tüm hedef gruplardan çıkar (Eksik olan kısım buradaydı)
          target_groups.each do |group_name_or_id|
            group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
            group.remove(@user) if group && group.users.include?(@user)
          end
        end
      end
    end
  end
end