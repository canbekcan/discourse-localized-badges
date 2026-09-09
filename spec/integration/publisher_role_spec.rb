# frozen_string_literal: true

require 'rails_helper'

describe 'Publisher Role and Badge Assignment Integration' do
  # 1. Test ortamı için sahte grup ve rozet oluşturuluyor
  let(:publisher_group) { Fabricate(:group, name: 'Publishers') }
  let!(:publisher_badge) { Fabricate(:badge, name: 'Verified Publisher') }
  let(:allowed_domain) { 'press.edu.tr' }
  
  # 2. Her testten önce Admin panelindeki SiteSettings ayarları taklit ediliyor
  before do
    SiteSetting.publisher_email_domains = allowed_domain
    SiteSetting.publisher_target_groups = publisher_group.id.to_s
  end

  # ====================================================================
  # SENARYO 1: Servis Atama Testleri (AssignPublisherRole)
  # ====================================================================
  describe LocalizedBadges::Services::AssignPublisherRole do
    it 'Geçerli yayıncı domaini ile gelen kullanıcıyı gruba ekler ve rozet verir' do
      user = Fabricate(:user, email: "editor@#{allowed_domain}")
      
      LocalizedBadges::Services::AssignPublisherRole.new(user).call
      
      expect(publisher_group.users).to include(user)
      expect(user.badges).to include(publisher_badge)
    end

    it 'Geçersiz domain (örn: gmail) ile gelen kullanıcıya işlem yapmaz' do
      user = Fabricate(:user, email: "editor@gmail.com")
      
      LocalizedBadges::Services::AssignPublisherRole.new(user).call
      
      expect(publisher_group.users).not_to include(user)
      expect(user.badges).not_to include(publisher_badge)
    end
  end

  # ====================================================================
  # SENARYO 2: Anında İptal (Instant Revoke) Testi (UserEmail Patch)
  # ====================================================================
  describe 'Instant Revoke on Email Change' do
    it 'Yayıncı yetkisi olan biri e-postasını yetkisiz bir domainle değiştirirse gruptan atılır ve rozeti silinir' do
      
      # Adım A: Zaten yayıncı olan bir kullanıcı simüle ediliyor
      user = Fabricate(:user, email: "author@#{allowed_domain}")
      publisher_group.add(user)
      BadgeGranter.grant(publisher_badge, user)
      
      # Başlangıçta yetkileri var mı diye teyit ediyoruz
      expect(publisher_group.users).to include(user)
      expect(user.badges).to include(publisher_badge)

      # Adım B: Kullanıcı ayarlardan e-postasını değiştiriyor (after_commit tetiklenir)
      user_email = user.user_emails.find_by(primary: true)
      user_email.update!(email: 'newemail@gmail.com')

      # Adım C: Veritabanı yenileniyor ve yetkilerinin anında alındığı doğrulanıyor
      user.reload
      expect(publisher_group.users).not_to include(user)
      expect(user.badges).not_to include(publisher_badge)
    end
  end
end