# frozen_string_literal: true

module Jobs
  class AssignRetroactiveSponsorBadges < ::Jobs::Base
    def execute(args)
      domain = args[:domain].to_s.downcase
      return if domain.blank?

      User.joins(:user_emails)
          .where("user_emails.email ILIKE ?", "%@#{domain}")
          .where(active: true)
          .find_each do |user|
        LocalizedBadges::Services::AssignSponsorBadges.new(user).call
      end
    end
  end
end