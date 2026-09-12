# frozen_string_literal: true

module LocalizedBadges
  module Services
    class AssignPublisherBadges
      def initialize(user)
        @user = user
        @domain = user.email&.split('@')&.last&.downcase
      end

      def call
        if @domain.blank?
          Rails.logger.debug("DevOps [AssignPublisherBadges]: Kullanici #{@user.id} icin domain bos, atlanıyor.")
          return
        end

        unless @user.active?
          Rails.logger.debug("DevOps [AssignPublisherBadges]: Kullanici #{@user.id} aktif degil, atlaniyor.")
          return
        end

        DistributedMutex.synchronize("assign_publisher_badge_#{@user.id}") do
          ActiveRecord::Base.transaction do
            badge = Badge.find_by(name: 'badges.verified_publisher.name') ||
                    Badge.find_by(name: 'Verified Publisher')

            unless badge
              Rails.logger.warn("DevOps [AssignPublisherBadges]: 'Verified Publisher' rozeti veritabaninda bulunamadi! Migrasyon calistirilmis mi kontrol edin.")
              return
            end

            domain_list = SiteSetting.localized_badges_publisher_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
            target_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)

            if domain_list.include?(@domain)
              BadgeGranter.grant(badge, @user)
              Rails.logger.info("DevOps [AssignPublisherBadges]: #{@user.username} (#{@user.email}) kullanicisina Verified Publisher rozeti verildi.")

              target_groups.each do |group_name_or_id|
                group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
                group.add(@user) if group && !group.users.include?(@user)
              end
            else
              user_badge = UserBadge.find_by(user_id: @user.id, badge_id: badge.id)
              if user_badge
                BadgeGranter.revoke(user_badge)
                Rails.logger.info("DevOps [AssignPublisherBadges]: #{@user.username} (#{@user.email}) kullanicisinin Verified Publisher rozeti geri alindi.")
              end

              target_groups.each do |group_name_or_id|
                group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
                group.remove(@user) if group && group.users.include?(@user)
              end
            end
          end
        end
      end
    end
  end
end