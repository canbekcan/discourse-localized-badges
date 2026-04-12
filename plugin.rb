# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  # Eklenti kapalıysa işlem yapma
  next unless SiteSetting.localized_badges_enabled

  reloadable_patch do
    
    # 1. API YAMASI: Badge Serializer (Rozetler sayfası ve listeler için)
    module ::LocalizedBadgeSerializerPatch
      def name
        object.name.to_s.start_with?('badges.') ? I18n.t(object.name) : super
      end

      def description
        object.description.to_s.start_with?('badges.') ? I18n.t(object.description) : super
      end
    end

    require_dependency 'badge_serializer'
    class ::BadgeSerializer
      prepend ::LocalizedBadgeSerializerPatch
    end

    # 2. API YAMASI: User Badge Serializer (Kullanıcı profilindeki rozetler için)
    module ::LocalizedUserBadgeSerializerPatch
      def badge_name
        object.badge.name.to_s.start_with?('badges.') ? I18n.t(object.badge.name) : super
      end
    end

    require_dependency 'user_badge_serializer'
    class ::UserBadgeSerializer
      prepend ::LocalizedUserBadgeSerializerPatch
    end

    # 3. MODEL YAMASI: Sunucu içi işlemler, bildirimler ve e-postalar için
    module ::LocalizedBadgeModelPatch
      def display_name
        name.to_s.start_with?('badges.') ? I18n.t(name) : super
      end
    end

    require_dependency 'badge'
    class ::Badge
      prepend ::LocalizedBadgeModelPatch
    end

  end
end