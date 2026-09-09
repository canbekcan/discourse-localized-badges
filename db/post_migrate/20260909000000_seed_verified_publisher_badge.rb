# frozen_string_literal: true

Badge.find_or_create_by!(name: 'Verified Publisher') do |badge|
  badge.description = 'Awarded to users registered with verified publisher domains.'
  badge.badge_type_id = 3 # 1: Altın, 2: Gümüş, 3: Bronz
  badge.system = true
  badge.allow_title = true
end