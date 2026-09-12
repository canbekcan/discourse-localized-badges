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

  # ====================================================================
  # 1. AYAR DEĞİŞİMİ KANCASI
  #    Admin panelden domain/grup ayarları değiştiğinde otomatik tarama
  # ====================================================================
  on(:site_setting_changed) do |setting_name, old_value, new_value|

    # --- A) Sponsor/Partner Domain Ayarları ---
    # Domain eklendiğinde: o domaine sahip kullanıcılara rozet ver
    # Domain silindiğinde: o domaine sahip kullanıcılardan rozeti al
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

      changed_domains.each do |domain|
        Jobs.enqueue(:assign_retroactive_sponsor_badges, domain: domain)
      end
    end

    # --- B) Yayıncı (Publisher) Domain Ayarı ---
    # Domain eklendiğinde: o domaine sahip kullanıcılara rozet ver + gruplara ekle
    # Domain silindiğinde: o domaine sahip kullanıcılardan rozeti al + gruplardan çıkar
    if setting_name == :localized_badges_publisher_domains
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)
      changed_domains = (new_domains - old_domains + old_domains - new_domains).uniq

      changed_domains.each do |domain|
        Jobs.enqueue(:assign_retroactive_publisher_badges, domain: domain)
      end
    end

    # --- C) Verified Akademik Domain Ayarı ---
    # Domain değiştiğinde: SQL sorgusu üzerinden tüm kullanıcıları yeniden tara
    # BadgeGranter.backfill hem rozet verme hem auto_revoke ile geri alma yapar
    if setting_name == :verified_academic_domains
      Jobs.enqueue(:backfill_verified_badge)
    end

    # --- D) Yayıncı Hedef Grupları (publisher_target_groups) ---
    # Grup eklendiğinde: mevcut rozet sahiplerini yeni gruba ekle
    # Grup silindiğinde: SADECE rozet sahiplerini gruptan çıkar (diğer üyelere dokunma)
    if setting_name == :publisher_target_groups
      old_groups = old_value.to_s.split('|').reject(&:blank?)
      new_groups = new_value.to_s.split('|').reject(&:blank?)
      added_groups = new_groups - old_groups
      removed_groups = old_groups - new_groups

      publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

      if publisher_badge
        badge_holders = User.joins(:user_badges).where(user_badges: { badge_id: publisher_badge.id })

        # Yeni eklenen gruplara mevcut rozet sahiplerini ekle
        if added_groups.any?
          badge_holders.find_each do |user|
            added_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.add(user) if group && !group.users.include?(user)
            end
          end
        end

        # Silinen gruplardan SADECE rozet sahiplerini çıkar
        if removed_groups.any?
          badge_holders.find_each do |user|
            removed_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(user) if group && group.users.include?(user)
            end
          end
        end
      end
    end
  end

  # ====================================================================
  # 2. YAYINCI OTOMASYONU: Model Seviyesinde Takip
  #    Kullanıcı oluşturulduğunda veya güncellendiğinde yayıncı kontrolü
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

        user_email = primary_email_record.email.to_s.downcase
        domain = user_email.split('@').last.to_s

        pub_domains = SiteSetting.localized_badges_publisher_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
        pub_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)

        is_valid = pub_domains.any? { |pd| domain == pd || domain.end_with?(".#{pd}") }
        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

        if is_valid
          # Gruplara ekle
          pub_groups.each do |group_name_or_id|
            group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
            group.add(self) if group && !group.users.include?(self)
          end

          # Rozet ver
          if publisher_badge && !self.user_badges.exists?(badge_id: publisher_badge.id)
            BadgeGranter.grant(publisher_badge, self)
          end
        else
          # Rozet ve gruplardan çıkar
          if publisher_badge && self.user_badges.exists?(badge_id: publisher_badge.id)
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
    # 3. E-POSTA DEĞİŞİMİ: ANINDA ROZET KONTROLÜ (INSTANT REVOKE)
    #    Kullanıcı birincil e-postasını değiştirdiğinde eşleşmeyen
    #    TÜM rozetleri anında geri al (Verified, Sponsor, Publisher)
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

          is_valid = allowed_domains.any? do |ad|
            domain == ad || domain.end_with?(".#{ad}")
          end

          unless is_valid
            ub = UserBadge.find_by(user_id: user.id, badge_id: verified_badge.id)
            if ub
              BadgeGranter.revoke(ub)
              Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini #{self.email} yapti. Verified rozeti ANINDA iptal edildi.")
            end
          end
        end

        # --- B) YAYINCI ROZETİ VE GRUPLARI ---
        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

        if publisher_badge && user.user_badges.exists?(badge_id: publisher_badge.id)
          pub_domains = SiteSetting.localized_badges_publisher_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
          pub_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)

          is_pub_valid = pub_domains.any? do |pd|
            domain == pd || domain.end_with?(".#{pd}")
          end

          unless is_pub_valid
            pub_ub = UserBadge.find_by(user_id: user.id, badge_id: publisher_badge.id)
            BadgeGranter.revoke(pub_ub) if pub_ub

            pub_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(user) if group && group.users.include?(user)
            end

            Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini degistirdi. Yayinici rozetinden ve gruplarindan ANINDA cikarildi.")
          end
        end

        # --- C) SPONSOR ROZETLERİ (Gold, Silver, Bronze Sponsor + Verified Partner) ---
        sponsor_badges_config = {
          'Gold Sponsor' => :localized_badges_gold_sponsor_domains,
          'Silver Sponsor' => :localized_badges_silver_sponsor_domains,
          'Bronze Sponsor' => :localized_badges_bronze_sponsor_domains,
          'Verified Partner' => :localized_badges_partner_domains,
        }

        sponsor_badges_config.each do |badge_name, setting_sym|
          sponsor_badge = Badge.find_by(name: badge_name)
          next unless sponsor_badge && user.user_badges.exists?(badge_id: sponsor_badge.id)

          sponsor_domains = SiteSetting.public_send(setting_sym).to_s.split('|').reject(&:blank?).map(&:downcase)

          is_sponsor_valid = sponsor_domains.any? do |sd|
            domain == sd || domain.end_with?(".#{sd}")
          end

          unless is_sponsor_valid
            sponsor_ub = UserBadge.find_by(user_id: user.id, badge_id: sponsor_badge.id)
            if sponsor_ub
              BadgeGranter.revoke(sponsor_ub)
              Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini #{self.email} yapti. #{badge_name} rozeti ANINDA iptal edildi.")
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