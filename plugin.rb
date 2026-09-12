# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 1.6
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-localized-badges

# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  next unless SiteSetting.localized_badges_enabled
  require_relative 'lib/localized_badges/services/assign_sponsor_badges'
  require_relative 'lib/localized_badges/services/assign_publisher_badges'
  require_relative 'app/jobs/regular/assign_retroactive_sponsor_badges'
  require_relative 'app/jobs/regular/assign_retroactive_publisher_badges'
  require_relative 'app/jobs/regular/backfill_verified_badge'
  require_relative 'app/jobs/regular/evaluate_retroactive_publisher_badges'

  # ====================================================================
  # 1. AYAR DEĞİŞİMİ KANCASI
  # ====================================================================
  on(:site_setting_changed) do |setting_name, old_value, new_value|

    # --- A) Sponsor/Partner Domain Ayarları ---
    sponsor_settings = %i[
      localized_badges_gold_sponsor_domains
      localized_badges_silver_sponsor_domains
      localized_badges_bronze_sponsor_domains
      localized_badges_partner_domains
    ]

    if sponsor_settings.include?(setting_name)
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)
      changed_domains = (new_domains - old_domains + old_domains - new_domains).uniq

      Rails.logger.info("DevOps [SettingChanged]: #{setting_name} degisti. Degisen domainler: #{changed_domains.inspect}")

      changed_domains.each do |domain|
        Jobs.enqueue(:assign_retroactive_sponsor_badges, domain: domain)
      end
    end

    # --- B) Yayıncı (Publisher) Domain Ayarı ---
    if setting_name == :localized_badges_publisher_domains
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)
      changed_domains = (new_domains - old_domains + old_domains - new_domains).uniq

      Rails.logger.info("DevOps [SettingChanged]: Publisher domainleri degisti. Degisen: #{changed_domains.inspect}")

      changed_domains.each do |domain|
        Jobs.enqueue(:assign_retroactive_publisher_badges, domain: domain)
      end
    end

    # --- C) Verified Akademik Domain Ayarı ---
    if setting_name == :verified_academic_domains
      Rails.logger.info("DevOps [SettingChanged]: Verified akademik domainler degisti. Backfill baslıyor.")
      Jobs.enqueue(:backfill_verified_badge)
    end

    # --- D) Yayıncı Hedef Grupları ---
    if setting_name == :publisher_target_groups
      old_groups = old_value.to_s.split('|').reject(&:blank?)
      new_groups = new_value.to_s.split('|').reject(&:blank?)
      added_groups = new_groups - old_groups
      removed_groups = old_groups - new_groups

      publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

      if publisher_badge
        badge_holders = User.joins(:user_badges).where(user_badges: { badge_id: publisher_badge.id })

        if added_groups.any?
          Rails.logger.info("DevOps [SettingChanged]: Yeni publisher gruplari eklendi: #{added_groups.inspect}. #{badge_holders.count} rozet sahibi gruplara ekleniyor.")
          badge_holders.find_each do |user|
            added_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.add(user) if group && !group.users.include?(user)
            end
          end
        end

        if removed_groups.any?
          Rails.logger.info("DevOps [SettingChanged]: Publisher gruplari silindi: #{removed_groups.inspect}. Sadece rozet sahipleri cikariliyor.")
          badge_holders.find_each do |user|
            removed_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(user) if group && group.users.include?(user)
            end
          end
        end
      else
        Rails.logger.warn("DevOps [SettingChanged]: publisher_target_groups degisti ama Verified Publisher rozeti bulunamadi!")
      end
    end
  end

  # ====================================================================
  # 2. YAYINCI OTOMASYONU: Model Seviyesinde Takip
  # ====================================================================
  reloadable_patch do
    module ::LocalizedPublisherUserPatch
      extend ActiveSupport::Concern

      included do
        after_commit :check_and_assign_publisher_role, on: [:create, :update]
      end

      def check_and_assign_publisher_role
        return if self.staff?

        primary_email_record = self.user_emails.find_by(primary: true)
        return unless primary_email_record.present?

        domain = primary_email_record.email.to_s.downcase.split('@').last.to_s

        pub_domains = SiteSetting.localized_badges_publisher_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
        pub_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)

        is_valid = pub_domains.any? { |pd| domain == pd || domain.end_with?(".#{pd}") }
        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

        return unless publisher_badge

        if is_valid
          pub_groups.each do |group_name_or_id|
            group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
            group.add(self) if group && !group.users.include?(self)
          end

          unless self.user_badges.exists?(badge_id: publisher_badge.id)
            BadgeGranter.grant(publisher_badge, self)
          end
        else
          if self.user_badges.exists?(badge_id: publisher_badge.id)
            user_badge = UserBadge.find_by(user_id: self.id, badge_id: publisher_badge.id)
            BadgeGranter.revoke(user_badge) if user_badge

            pub_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(self) if group && group.users.include?(self)
            end
          end
        end
      end
    end

    require_dependency 'user'
    class ::User
      include ::LocalizedPublisherUserPatch
    end

    # ====================================================================
    # 3. E-POSTA DEĞİŞİMİ: ANINDA ROZET KONTROLÜ
    # ====================================================================
    module ::LocalizedUserEmailPatch
      extend ActiveSupport::Concern

      included do
        after_commit :check_all_badges_on_email_change, on: [:create, :update]
      end

      def check_all_badges_on_email_change
        return unless self.primary?

        user = self.user
        return if user.nil? || user.staff?

        domain = self.email.to_s.split('@').last.to_s.downcase

        # --- A) VERIFIED ROZETİ ---
        verified_badge = Badge.find_by(name: 'Verified') || Badge.find_by(name: 'badges.verified.name')

        if verified_badge && user.user_badges.exists?(badge_id: verified_badge.id)
          allowed_domains = SiteSetting.verified_academic_domains.to_s.split('|').reject(&:blank?).map(&:downcase)

          is_valid = allowed_domains.any? { |ad| domain == ad || domain.end_with?(".#{ad}") }

          unless is_valid
            ub = UserBadge.find_by(user_id: user.id, badge_id: verified_badge.id)
            if ub
              BadgeGranter.revoke(ub)
              Rails.logger.info("DevOps [EmailChange]: #{user.username} -> #{self.email}. Verified rozeti iptal edildi.")
            end
          end
        end

        # --- B) YAYINCI ROZETİ ---
        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

        if publisher_badge && user.user_badges.exists?(badge_id: publisher_badge.id)
          pub_domains = SiteSetting.localized_badges_publisher_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
          pub_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)

          is_pub_valid = pub_domains.any? { |pd| domain == pd || domain.end_with?(".#{pd}") }

          unless is_pub_valid
            pub_ub = UserBadge.find_by(user_id: user.id, badge_id: publisher_badge.id)
            BadgeGranter.revoke(pub_ub) if pub_ub

            pub_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(user) if group && group.users.include?(user)
            end

            Rails.logger.info("DevOps [EmailChange]: #{user.username} -> #{self.email}. Publisher rozeti ve gruplari iptal edildi.")
          end
        end

        # --- C) SPONSOR ROZETLERİ ---
        {
          'Gold Sponsor' => :localized_badges_gold_sponsor_domains,
          'Silver Sponsor' => :localized_badges_silver_sponsor_domains,
          'Bronze Sponsor' => :localized_badges_bronze_sponsor_domains,
          'Verified Partner' => :localized_badges_partner_domains,
        }.each do |badge_name, setting_sym|
          sponsor_badge = Badge.find_by(name: badge_name)
          next unless sponsor_badge && user.user_badges.exists?(badge_id: sponsor_badge.id)

          sponsor_domains = SiteSetting.public_send(setting_sym).to_s.split('|').reject(&:blank?).map(&:downcase)
          is_valid = sponsor_domains.any? { |sd| domain == sd || domain.end_with?(".#{sd}") }

          unless is_valid
            sponsor_ub = UserBadge.find_by(user_id: user.id, badge_id: sponsor_badge.id)
            if sponsor_ub
              BadgeGranter.revoke(sponsor_ub)
              Rails.logger.info("DevOps [EmailChange]: #{user.username} -> #{self.email}. #{badge_name} rozeti iptal edildi.")
            end
          end
        end
      end
    end

    require_dependency 'user_email'
    class ::UserEmail
      include ::LocalizedUserEmailPatch
    end

  end
end