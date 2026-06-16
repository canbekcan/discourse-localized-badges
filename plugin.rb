# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 1.1
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-localized-badges

# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  next unless SiteSetting.localized_badges_enabled

  # ====================================================================
  # OTOMASYON 1: "Verified" rozeti alanları otomatik olarak TL1 yap ve kilitle
  # ====================================================================
  DiscourseEvent.on(:user_badge_granted) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')
    
    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)
      
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
  DiscourseEvent.on(:user_badge_removed) do |badge_id, user_id|
    target_badge = Badge.find_by(name: 'badges.verified.name') || Badge.find_by(name: 'Verified')
    
    if target_badge && badge_id == target_badge.id
      user = User.find_by(id: user_id)
      
      # Kullanıcının mevcut yetkisi TL1 veya üzerindeyse onu TL0'a (Ziyaretçi seviyesi) geri çekiyoruz
      if user && user.trust_level > TrustLevel[0]
        user.change_trust_level!(TrustLevel[0])
        
        # Kullanıcının üzerindeki güven seviyesi kilidini NULL yaparak kaldırıyoruz.
        # Bu sayede sistemin standart mekanizmaları bozulmaz.
        user.update_column(:manual_locked_trust_level, nil)
        
        Rails.logger.info("DevOps [discourse-localized-badges]: Kullanici (ID: #{user.id}) e-postasini degistirdigi ve rozetini kaybettigi icin TL0'a dusuruldu ve kilidi kaldirildi.")
      end
    end
  end

  # ====================================================================
  # YAMALAR (PATCHES): Çeviri ve Serileştirme İşlemleri
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

  end
end