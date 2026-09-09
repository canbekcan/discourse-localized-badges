# frozen_string_literal: true

Badge.create_unless_exists!(
  name: 'Verified Publisher',
  description: 'Awarded to users registered with verified publisher domains.',
  badge_type_id: 3, # 1: Altın, 2: Gümüş, 3: Bronz
  system: true,
  allow_title: true
)