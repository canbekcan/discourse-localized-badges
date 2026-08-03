# frozen_string_literal: true

class SeedSponsorBadges < ActiveRecord::Migration[7.0]
  def up
    badges = [
      { name: 'Gold Sponsor', icon: 'award' },
      { name: 'Silver Sponsor', icon: 'medal' },
      { name: 'Bronze Sponsor', icon: 'certificate' },
      { name: 'Verified Partner', icon: 'handshake' }
    ]

    badges.each do |b|
      Badge.find_or_initialize_by(name: b[:name]).tap do |badge|
        badge.badge_type_id = 1 
        badge.icon = b[:icon]
        badge.description = "badges.#{b[:key]}.description"
        badge.long_description = "badges.#{b[:key]}.long_description"
        badge.allow_title = true
        badge.system = true
        badge.save!
      end
    end
  end

  def down
    # Sistem rozetleri geriye dönük uyumluluk ve veri kaybını önlemek adına genellikle silinmez.
  end
end