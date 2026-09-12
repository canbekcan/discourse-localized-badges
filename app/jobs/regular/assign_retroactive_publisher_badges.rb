# frozen_string_literal: true

module Jobs
  class AssignRetroactivePublisherBadges < ::Jobs::Base
    def execute(args)
      domain = args[:domain].to_s.downcase
      return if domain.blank?

      users = User.joins(:user_emails)
                  .where("user_emails.email ILIKE ?", "%@#{domain}")
                  .where(active: true)

      Rails.logger.info("DevOps [RetroactivePublisher]: '#{domain}' domaini icin #{users.count} kullanici bulundu, taranıyor...")

      users.find_each do |user|
        LocalizedBadges::Services::AssignPublisherBadges.new(user).call
      end
    end
  end
end