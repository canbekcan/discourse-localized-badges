# frozen_string_literal: true

class LocalizeFirstAuthorBadge < ActiveRecord::Migration[7.0]
  def up
    # Rozeti bul ve isim/açıklama alanlarını I18n anahtarlarıyla güncelle
    badge = Badge.find_by(name: 'First Author')
    
    if badge
      badge.update_columns(
        name: 'badges.first_author.name',
        description: 'badges.first_author.description'
      )
    end
  end

  def down
    # Gerekirse geri alma işlemi
    badge = Badge.find_by(name: 'badges.first_author.name')
    
    if badge
      badge.update_columns(
        name: 'First Author',
        description: 'Awarded for publishing your first topic.'
      )
    end
  end
end