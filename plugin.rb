# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 1.4
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-localized-badges

# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  next unless SiteSetting.localized_badges_enabled
  require_relative 'lib/localized_badges/services/assign_sponsor_badges'
  require_relative 'lib/localized_badges/services/assign_publisher_role'
  require_relative 'app/jobs/regular/assign_retroactive_sponsor_badges'
  require_relative 'app/jobs/regular/evaluate_retroactive_publisher_badges'

  # 1. AYAR DEĞİŞİMİ KANCASI: Yeni domain eklendiğinde veya SİLİNDİĞİNDE mevcut kullanıcıları tara
  on(:site_setting_changed) do |setting_name, old_value, new_value|
    
    # Sponsor Rozetleri Taraması
    sponsor_settings = %i[
      localized_badges_gold_sponsor_domains
      localized_badges_silver_sponsor_domains
      localized_badges_bronze_sponsor_domains
      localized_badges_partner_domains
    ]

    if sponsor_settings.include?(setting_name)
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)

      added_domains = new_domains - old_domains
      removed_domains = old_domains - new_domains
      
      (added_domains + removed_domains).uniq.each do |domain|
        Jobs.enqueue(:assign_retroactive_sponsor_badges, domain: domain)
      end
    end

    # Yayıncı Rozetleri Taraması (Yeni Eklendi)
    if setting_name == :publisher_email_domains
      old_domains = old_value.to_s.split('|').map(&:downcase)
      new_domains = new_value.to_s.split('|').map(&:downcase)

      added_domains = new_domains - old_domains
      removed_domains = old_domains - new_domains
      
      (added_domains + removed_domains).uniq.each do |domain|
        Jobs.enqueue(:evaluate_retroactive_publisher_badges, domain: domain)
      end
    end
  end

  # 2. KULLANICI AKTİVASYON KANCASI
  on(:user_activated) do |user|
    LocalizedBadges::Services::AssignSponsorBadges.new(user).call
    LocalizedBadges::Services::AssignPublisherRole.new(user).call
  end

  # 3. E-POSTA GÜNCELLEME KANCASI
  on(:user_emails_changed) do |user|
    LocalizedBadges::Services::AssignSponsorBadges.new(user).call
    LocalizedBadges::Services::AssignPublisherRole.new(user).call
  end

  # ====================================================================
  # OTOMASYON 1: "Verified" rozeti alanları otomatik olarak TL1 yap
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
  # OTOMASYON 2: "Verified" rozeti geri alınanları TL0'a DÜŞÜR
  # ====================================================================
  DiscourseEvent.on(:user_badge_revoked) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')
    
    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)
      
      next if user && user.staff? 
      
      if user && user.trust_level > TrustLevel[0]
        user.update_column(:manual_locked_trust_level, nil) if user.manual_locked_trust_level.present?
        user.change_trust_level!(TrustLevel[0])
        Rails.logger.info("DevOps [discourse-localized-badges]: Kullanici (ID: #{user.id}) e-postasini degistirdigi ve rozetini kaybettigi icin TL0'a dusuruldu.")
      end
    end
  end

  # ====================================================================
  # YAMALAR (PATCHES): Çeviri, Serileştirme ve ANLIK E-POSTA KONTROLÜ
  # ====================================================================
  reloadable_patch do
    
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
    # 4. ANINDA E-POSTA DEĞİŞİMİ YAKALAYICI (INSTANT REVOKE)
    # ====================================================================
    module ::LocalizedUserEmailPatch
      extend ActiveSupport::Concern

      included do
        after_commit :check_verified_academic_badge, on: [:create, :update]
      end

      def check_verified_academic_badge
        return unless self.primary?

        user = self.user
        return if user.nil? || user.staff?

        domain = self.email.to_s.split('@').last.to_s.downcase

        # VERIFIED ROZETİ KONTROLÜ (ORİJİNAL)
        target_badge = Badge.find_by(name: 'Verified')
        
        if target_badge && user.user_badges.exists?(badge_id: target_badge.id)
          allowed_domains = SiteSetting.verified_academic_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
          
          is_valid = allowed_domains.any? do |ad|
            domain == ad || domain.end_with?(".#{ad}")
          end

          unless is_valid
            user_badge = UserBadge.find_by(user_id: user.id, badge_id: target_badge.id)
            if user_badge
              BadgeGranter.revoke(user_badge)
              Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini #{self.email} yapti. Kurumsal olmadigi icin rozeti ANINDA iptal edildi.")
            end
          end
        end

        # YAYINCI ROZETİ VE GRUP KONTROLÜ
        publisher_badge = Badge.find_by(name: 'badges.verified_publisher.name') || Badge.find_by(name: 'Verified Publisher')
        
        if publisher_badge && user.user_badges.exists?(badge_id: publisher_badge.id)
          pub_domains = SiteSetting.publisher_email_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
          pub_groups = SiteSetting.publisher_target_groups.to_s.split('|').reject(&:blank?)
          
          is_pub_valid = pub_domains.any? do |pd| 
            domain == pd || domain.end_with?(".#{pd}") 
          end

          unless is_pub_valid
            pub_user_badge = UserBadge.find_by(user_id: user.id, badge_id: publisher_badge.id)
            BadgeGranter.revoke(pub_user_badge) if pub_user_badge
            
            pub_groups.each do |group_name_or_id|
              group = Group.find_by(name: group_name_or_id) || Group.find_by(id: group_name_or_id)
              group.remove(user) if group && group.users.include?(user)
            end
            
            Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini degistirdi. Yayinici gruplarindan ve rozetinden ANINDA cikarildi.")
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