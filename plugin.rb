# name: discourse-localized-badges
# about: Custom badges localisation for Discourse
# version: 0.1
# authors: Senior Engineer
# url: https://github.com/canbekcan/discourse-localized-badges.git

enabled_site_setting :localized_badges_enabled

after_initialize do
  # Bu blok, uygulama ayağa kalktığında çalışır.
  # Rozet isimleri 'badges.first_author.name' formatında olduğunda 
  # Discourse otomatik olarak I18n sistemine bakar.
end