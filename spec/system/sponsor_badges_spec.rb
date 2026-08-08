# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Localized Badges - Sponsor Assignment", type: :system do
  # Fab! ile test ortamı için veritabanında geçici ve hızlı kullanıcılar oluşturulur
  fab!(:admin)
  fab!(:gold_sponsor_user) { Fabricate(:user, email: "sponsor@bekcan.com", active: true) }
  
  before do
    SiteSetting.localized_badges_enabled = true
    # Rozetin veritabanında var olduğundan emin ol
    Badge.find_or_create_by!(name: 'Gold Sponsor', badge_type_id: 1)
  end

  it "enqueues the AssignRetroactiveSponsorBadges job when a new domain is added" do
    # Site ayarı simülasyonu
    old_domains = ""
    new_domains = "bekcan.com"

    # Sidekiq kuyruğunun (Job) tetiklendiğini doğrula
    expect {
      DiscourseEvent.trigger(
        :site_setting_changed, 
        :localized_badges_gold_sponsor_domains, 
        old_domains, 
        new_domains
      )
    }.to change { Jobs::AssignRetroactiveSponsorBadges.jobs.size }.by(1)
    
    # Kuyruktaki görevin doğru parametreyle (domain: bekcan.com) çağrıldığını doğrula
    job_args = Jobs::AssignRetroactiveSponsorBadges.jobs.last['args'].first
    expect(job_args['domain']).to eq("bekcan.com")
  end
end