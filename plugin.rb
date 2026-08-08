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

  # 1. AYAR DEĞİŞİMİ KANCASI: Yeni domain eklendiğinde mevcut kullanıcıları tara
  on(:site_setting_changed) do |setting_name, old_value, new_value|
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

      added_domains.each do |domain|
        # Zeitwerk, Jobs::AssignRetroactiveSponsorBadges sınıfını app/jobs klasöründen otomatik yükler
        Jobs.enqueue(:assign_retroactive_sponsor_badges, domain: domain)
      end
    end
  end

  # 2. KULLANICI AKTİVASYON KANCASI
  on(:user_activated) do |user|
    LocalizedBadges::Services::AssignSponsorBadges.new(user).call
  end

  # 3. E-POSTA GÜNCELLEME KANCASI
  on(:user_emails_changed) do |user|
    LocalizedBadges::Services::AssignSponsorBadges.new(user).call
  end

  # ====================================================================
  # OTOMASYON 1: "Verified" rozeti alanları otomatik olarak TL1 yap ve kilitle
  # ====================================================================
  DiscourseEvent.on(:user_badge_granted) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')
    
    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)
      
      # GÜVENLİK YAMASI 1: Eğer kullanıcı Admin veya Moderatör ise muaf tut
      next if user && user.staff?
      
      if user && user.trust_level < TrustLevel[1]
        user.change_trust_level!(TrustLevel[1])
        user.update_column(:manual_locked_trust_level, 1)
        
        Rails.logger.info("DevOps [discourse-localized-badges]: Kullanici (ID: #{user.id}) Verified rozeti aldigi icin TL1 yapildi ve kilitlendi.")
      end
    end
  end

  # ====================================================================
  # OTOMASYON 2: "Verified" rozeti geri alınanları TL0'a DÜŞÜR ve kilidi aç
  # ====================================================================
  DiscourseEvent.on(:user_badge_revoked) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')
    
    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)
      
      # GÜVENLİK YAMASI 2: Admin veya Moderatörleri muaf tut
      next if user && user.staff? 
      
      if user && user.trust_level > TrustLevel[0]
        # Önce kilidi kaldırıyoruz (nil yapıyoruz) ki change_trust_level! metodu çalışabilsin
        user.update_column(:manual_locked_trust_level, nil)
        user.change_trust_level!(TrustLevel[0])
        
        Rails.logger.info("DevOps [discourse-localized-badges]: Kullanici (ID: #{user.id}) e-postasini degistirdigi ve rozetini kaybettigi icin kilidi kaldirildi ve TL0'a dusuruldu.")
      end
    end
  end

  # ====================================================================
  # YAMALAR (PATCHES): Çeviri, Serileştirme ve ANLIK E-POSTA KONTROLÜ
  # ====================================================================
  reloadable_patch do
    
    # 1. Badge Serializer
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

    # 2. Badge Model
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

    # 3. Badge Grouping
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
    # 4. YENİ: ANINDA E-POSTA DEĞİŞİMİ YAKALAYICI (INSTANT REVOKE)
    # ====================================================================
    module ::LocalizedUserEmailPatch
      extend ActiveSupport::Concern

      included do
        after_commit :check_verified_academic_badge, on: [:create, :update]
      end

      def check_verified_academic_badge
        # Sadece "birincil (primary)" e-posta değişikliklerini yakala
        return unless self.primary?

        user = self.user
        return if user.nil? || user.staff?

        target_badge = Badge.find_by(name: 'Verified')
        
        # Eğer kullanıcının zaten Doğrulanmış rozeti YOKSA işlemi bitir
        return unless target_badge && user.user_badges.exists?(badge_id: target_badge.id)

        # Yeni yapılan e-postanın domainini al
        domain = self.email.to_s.split('@').last.to_s.downcase
        allowed_domains = SiteSetting.verified_academic_domains.to_s.split('|').reject(&:blank?).map(&:downcase)
        
        # Yeni domain, izin verilenler listesinde var mı?
        is_valid = allowed_domains.any? do |ad|
          domain == ad || domain.end_with?(".#{ad}")
        end

        # EĞER GEÇERSİZSE (Örn: gmail.com yapıldıysa):
        unless is_valid
          user_badge = UserBadge.find_by(user_id: user.id, badge_id: target_badge.id)
          if user_badge
            # 1. Rozeti anında geri al
            BadgeGranter.revoke(user_badge)
            
            # Not: Rozet geri alındığı an, yukarıdaki OTOMASYON 2 zincirleme olarak
            # tetiklenecek ve kullanıcıyı anında TL0 seviyesine düşürecektir.
            Rails.logger.info("DevOps [discourse-localized-badges]: #{user.username} e-postasini #{self.email} yapti. Kurumsal olmadigi icin rozeti ANINDA iptal edildi.")
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