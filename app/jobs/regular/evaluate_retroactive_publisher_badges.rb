# frozen_string_literal: true

module Jobs
  class EvaluateRetroactivePublisherBadges < ::Jobs::Base
    def execute(args)
      domain = args[:domain]
      return unless domain.present?

      # Domain ile biten tüm kullanıcı e-postalarını bul ve yeniden değerlendir
      UserEmail.where("email LIKE ?", "%@#{domain}").find_each do |user_email|
        user = user_email.user
        next if user.nil? || user.staff?
        
        LocalizedBadges::Services::AssignPublisherRole.new(user).call
      end
    end
  end
end