# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 0.1
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-localized-badges

# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  next unless SiteSetting.localized_badges_enabled

  reloadable_patch do
    
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

    module ::LocalizedUserBadgeSerializerPatch
      def badge_name
        object.badge.name.to_s.start_with?('badges.') ? I18n.t(object.badge.name) : super
      end
    end

    require_dependency 'user_badge_serializer'
    class ::UserBadgeSerializer
      prepend ::LocalizedUserBadgeSerializerPatch
    end

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