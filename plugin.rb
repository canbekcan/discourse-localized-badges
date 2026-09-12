# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 1.7
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

    # --- A) Sponsor/Publisher Domain Ayarları (5 ayar) ---
    badge_settings = %i[
      localized_badges_gold_sponsor_domains
      localized_badges_silver_sponsor_domains
      localized_badges_bronze_sponsor_domains
      localized_badges_partner_domains
      localized_badges_publisher_domains
    ]

    if badge_settings.include?(setting_name)
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)

      added_domains = new_domains - old_domains
      removed_domains = old_domains - new_domains

      (added_domains + removed_domains).uniq.each do |domain|
        Jobs.enqueue(:assign_retroactive_sponsor_badges, domain: domain)
        Jobs.enqueue(:assign_retroactive_publisher_badges, domain: domain)
      end
    end

    # --- B) Verified Akademik Domain Ayarı ---
    if setting_name == :verified_academic_domains
      Jobs.enqueue(:backfill_verified_badge)
    end

    # --- C) Yayıncı Hedef Grupları ---
    if setting_name == :publisher_target_groups
      old_groups = old_value.to_s.split('|').reject(&:blank?)
      new_groups = new_value.to_s.split('|').reject(&:blank?)
      added_groups = new_groups - old_groups
      removed_groups = old_groups - new_groups

      publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')

      if publisher_badge
        badge_holders = User.joins(:user_badges).where(user_badges: { badge_id: publisher_badge.id })

        if added_groups.any?
          badge_holders.find_each do |user|
            added_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.add(user) if group && !group.users.include?(user)
            end
          end
        end

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
  # 2. KULLANICI AKTİVASYON KANCASI
  # ====================================================================
  on(:user_activated) do |user|
    LocalizedBadges::Services::AssignSponsorBadges.new(user).call
    LocalizedBadges::Services::AssignPublisherBadges.new(user).call
  end

  # ====================================================================
  # 3. E-POSTA GÜNCELLEME KANCASI
  # ====================================================================
  on(:user_emails_changed) do |user|
    LocalizedBadges::Services::AssignSponsorBadges.new(user).call
    LocalizedBadges::Services::AssignPublisherBadges.new(user).call
  end

  # ====================================================================
  # 4. "Verified" rozeti alanları otomatik olarak TL1 yap
  # ====================================================================
  DiscourseEvent.on(:user_badge_granted) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')

    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)

      next if user && user.staff?

      if user && user.trust_level < TrustLevel[1]
        user.change_trust_level!(TrustLevel[1])
        Rails.logger.info("DevOps [discourse-localized-badges]: Kullanici (ID: #{user.id}) Verified rozeti aldigi icin TL1'e terfi ettirildi.")
      end
    end
  end

  # ====================================================================
  # 5. "Verified" rozeti geri alınanları TL0'a düşür
  # ====================================================================
  DiscourseEvent.on(:user_badge_revoked) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')

    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)

      next if user && user.staff?

      if user && user.trust_level > TrustLevel[0]
        user.update_column(:manual_locked_trust_level, nil) if user.manual_locked_trust_level.present?
        user.change_trust_level!(TrustLevel[0])
        Rails.logger.info("DevOps [discourse-localized-badges]: Kullanici (ID: #{user.id}) Verified rozeti kaybettigi icin TL0'a dusuruldu.")
      end
    end
  end

  # ====================================================================
  # 6. YAMALAR (PATCHES)
  # ====================================================================
  reloadable_patch do

    # --- Badge Serializer: i18n çeviri desteği ---
    module ::LocalizedBadgeSerializerPatch
      def name
        if object.name.to_s.start_with?('badges.')
          I18n.t(object.name)
        else
          defined?(super) ? super : object.name
        end
      end
      def description
        if object.description.to_s.start_with?('badges.')
          I18n.t(object.description)
        else
          defined?(super) ? super : object.description
        end
      end
      def long_description
        if object.long_description.to_s.start_with?('badges.')
          I18n.t(object.long_description)
        else
          defined?(super) ? super : object.long_description
        end
      end
    end

    require_dependency 'badge_serializer'
    class ::BadgeSerializer
      prepend ::LocalizedBadgeSerializerPatch
    end

    # --- Badge Model: display_name çeviri desteği ---
    module ::LocalizedBadgeModelPatch
      def display_name
        if name.to_s.start_with?('badges.')
          I18n.t(name)
        else
          defined?(super) ? super : name
        end
      end
    end

    require_dependency 'badge'
    class ::Badge
      prepend ::LocalizedBadgeModelPatch
    end

    # --- Badge Grouping Serializer ---
    module ::LocalizedBadgeGroupingSerializerPatch
      def name
        if object.name.to_s.start_with?('badge_groupings.')
          I18n.t(object.name)
        else
          defined?(super) ? super : object.name
        end
      end
    end

    require_dependency 'badge_grouping_serializer'
    class ::BadgeGroupingSerializer
      prepend ::LocalizedBadgeGroupingSerializerPatch
    end

    # ====================================================================
    # 7. ANINDA E-POSTA DEĞİŞİMİ YAKALAYICI (INSTANT REVOKE)
    #    Kullanıcı birincil e-postasını değiştirdiğinde
    #    eşleşmeyen TÜM rozetleri anında geri al
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
        verified_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')

        if verified_badge && user.user_badges.exists?(badge_id: verified_badge.id)
          allowed_domains = SiteSetting.verified_academic_domains.to_s.split('|').reject(&:blank?).map(&:downcase)

          is_valid = allowed_domains.any? { |ad| domain == ad || domain.end_with?(".#{ad}") }

          unless is_valid
            ub = UserBadge.find_by(user_id: user.id, badge_id: verified_badge.id)
            if ub
              BadgeGranter.revoke(ub)
              Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini #{self.email} yapti. Verified rozeti iptal edildi.")
            end
          end
        end

        # --- B) YAYINCI ROZETİ VE GRUPLARI ---
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

            Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini degistirdi. Yayinici rozetinden ve gruplarindan cikarildi.")
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
              Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} -> #{self.email}. #{badge_name} rozeti iptal edildi.")
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