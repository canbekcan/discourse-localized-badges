# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 1.5
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-localized-badges

# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  next unless SiteSetting.localized_badges_enabled
  require_relative 'lib/localized_badges/services/assign_sponsor_badges'
  require_relative 'app/jobs/regular/assign_retroactive_sponsor_badges'
  require_relative 'lib/localized_badges/services/assign_publisher_badges'
  require_relative 'app/jobs/regular/assign_retroactive_publisher_badges'

  # 1. AYAR DEĞİŞİMİ KANCASI (Sponsor ve Yayıncılar için)
  on(:site_setting_changed) do |setting_name, old_value, new_value|
    if setting_name == :localized_badges_publisher_domains
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)
      (new_domains - old_domains + old_domains - new_domains).uniq.each do |domain|
        Jobs.enqueue(:assign_retroactive_publisher_badges, domain: domain)
      end
    end
  end

  # ====================================================================
  # YAYINCI OTOMASYONU: Doğrudan Model Seviyesinde Takip (Asla Kaçmaz)
  # ====================================================================
  reloadable_patch do
    module ::LocalizedPublisherUserPatch
      extend ActiveSupport::Concern

      included do
        after_commit :check_and_assign_publisher_role, on: [:create, :update]
      end

      def check_and_assign_publisher_role
        return if self.staff?

        # Kullanıcının birincil e-postasını al
        primary_email_record = self.user_emails.find_by(primary: true)
        return unless primary_email_record.present?

        user_email = primary_email_record.email.to_s.downcase
        domain = user_email.split('@').last.to_s

        pub_domains = SiteSetting.localized_badges_publisher_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
        pub_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)
        
        is_valid = pub_domains.any? { |pd| domain == pd || domain.end_with?(".#{pd}") }
        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

        Rails.logger.info("DevOps [Publisher Check]: Kullanici #{self.username} (#{user_email}) kontrol ediliyor. Gecerli mi? #{is_valid}")

        if is_valid
          # 1. Gruplara Ekle
          pub_groups.each do |group_name_or_id|
            group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
            if group && !group.users.include?(self)
              group.add(self)
              Rails.logger.info("DevOps [Publisher Check]: #{self.username} yayinci grubuna eklendi: #{group.name}")
            end
          end

          # 2. Rozet Ver
          if publisher_badge && !self.user_badges.exists?(badge_id: publisher_badge.id)
            BadgeGranter.grant(publisher_badge, self)
            Rails.logger.info("DevOps [Publisher Check]: #{self.username} kullanicisina yayinci rozeti verildi.")
          end
        else
          # Listeden çıktıysa veya uymuyorsa geri al
          if publisher_badge && self.user_badges.exists?(badge_id: publisher_badge.id)
            user_badge = UserBadge.find_by(user_id: self.id, badge_id: publisher_badge.id)
            BadgeGranter.revoke(user_badge) if user_badge
            
            pub_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(self) if group && group.users.include?(self)
            end
            Rails.logger.info("DevOps [Publisher Check]: #{self.username} yayinci yetkileri ve rozeti geri alindi.")
          end
        end
      end
    end

    require_dependency 'user'
    class ::User
      include ::LocalizedPublisherUserPatch
    end
  end
end