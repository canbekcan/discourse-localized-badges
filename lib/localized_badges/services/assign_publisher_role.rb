# frozen_string_literal: true

module LocalizedBadges
  module Services
    class AssignPublisherRole
      def initialize(user)
        @user = user
      end

      def call
        return if @user.nil? || @user.staff?
        assign_roles_and_badges
      end

      private

      def assign_roles_and_badges
        domains = SiteSetting.publisher_email_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
        groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)
        
        return if domains.empty? || groups.empty?

        user_domain = @user.email.to_s.split('@').last.to_s.downcase
        is_valid = domains.any? { |d| user_domain == d || user_domain.end_with?(".#{d}") }

        if is_valid
          # Belirlenen tüm gruplara kullanıcıyı ekle
          groups.each do |group_id|
            group = Group.find_by(id: group_id)
            group.add(@user) if group && !group.users.include?(@user)
          end

          # Rozeti tanımla
          badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')
          BadgeGranter.grant(badge, @user) if badge && !@user.user_badges.exists?(badge_id: badge.id)
        end
      end
    end
  end
end