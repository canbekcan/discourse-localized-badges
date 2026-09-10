# frozen_string_literal: true

module Jobs
  class AssignRetroactivePublisherBadges < ::Jobs::Base
    def execute(args)
      domain = args[:domain].to_s.downcase
      return unless domain.present?

      User.joins(:user_emails)
          .where("user_emails.email ILIKE ?", "%@#{domain}")
          .where(active: true)
          .find_each do |user|
        LocalizedBadges::Services::AssignPublisherBadges.new(user).call
      end
    end
  end
end