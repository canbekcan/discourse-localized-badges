# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 1.1
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-localized-badges

# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  next unless SiteSetting.localized_badges_enabled

  reloadable_patch do
    
    # 1. Badge Serializer (Güvenli Yama)
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

    # 2. Backend ve E-postalar için (Güvenli Yama)
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

    # 3. Badge Grouping (Rozet Grupları) Çevirisi
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