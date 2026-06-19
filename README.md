It is for Discourse plugin to add localized badge names and descriptions.
https://meta.discourse.org/t/how-can-badges-and-groups-be-localized-multilingual/398127/9



----

```
./launcher enter app
rails c
```

```
badge = Badge.find_by(name: 'Verified')

if badge
  puts "DevOps: Eski uyeleri kurtarma (Backfill) operasyonu basliyor..."

  BadgeGranter.backfill(badge)

  count = 0
  UserBadge.where(badge_id: badge.id).find_each do |ub|
    user = ub.user
    # Sistem hesaplarini, botlari ve Yoneticileri atla
    next if user.nil? || user.id <= 0 || user.staff?
    
    if user.trust_level < 1 || user.manual_locked_trust_level != 1
      user.change_trust_level!(1)
      user.update_column(:manual_locked_trust_level, 1)
      count += 1
      puts "[Kurtarildi] #{user.username} -> Rozet iade edildi, TL1'e kilitlendi."
    end
  end
  
  puts "DevOps: Operasyon basariyla tamamlandi! Toplam #{count} uyenin haklari iade edildi."
else
  puts "Hata: 'Verified' rozeti veritabaninda bulunamadi!"
end
```