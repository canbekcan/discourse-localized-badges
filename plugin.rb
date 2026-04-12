# frozen_string_literal: true

enabled_site_setting :localized_badges_enabled

after_initialize do
  # Discourse, about.json ve locales dosyalarını 
  # otomatik olarak çözümleyecektir.
end