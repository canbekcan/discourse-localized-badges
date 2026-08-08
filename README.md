# Discourse Localized Badges

A Discourse plugin designed to support fully localized badge names and descriptions for multilingual communities. This ensures that users experience a seamless, native-language interface when viewing gamification and trust elements.

For more context on the underlying mechanics, refer to the official Discourse Meta discussion: [How can badges and groups be localized?](https://meta.discourse.org/t/how-can-badges-and-groups-be-localized-multilingual/398127)

## Installation

1. Access your Discourse server via SSH.
2. Open your `app.yml` configuration file (usually located in `/var/discourse/containers/app.yml`).
3. Add the plugin's repository URL to your `hooks` section:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone [https://github.com/canbekcan/discourse-localized-badges.git](https://github.com/canbekcan/discourse-localized-badges.git)

```

4. Rebuild the container to apply the changes:

```bash
cd /var/discourse
./launcher rebuild app

```

## Backfill Operation (DevOps)

If you are installing this plugin on an existing Discourse community, you may need to run a retroactive backfill operation to ensure legacy users receive their badges and corresponding Trust Level updates.

Enter your Discourse application container and open the Rails console:

```bash
./launcher enter app
rails c

```

Run the following Ruby script to execute the backfill:

```ruby
badge = Badge.find_by(name: 'Verified')

if badge
  puts "DevOps: Starting the retroactive backfill operation for existing members..."

  BadgeGranter.backfill(badge)

  count = 0
  UserBadge.where(badge_id: badge.id).find_each do |ub|
    user = ub.user
    
    # Skip system accounts, bots, and Staff
    next if user.nil? || user.id <= 0 || user.staff?
    
    if user.trust_level < 1 || user.manual_locked_trust_level != 1
      user.change_trust_level!(1)
      user.update_column(:manual_locked_trust_level, 1)
      count += 1
      puts "[Restored] #{user.username} -> Badge restored and locked to TL1."
    end
  end
  
  puts "DevOps: Operation successfully completed! A total of #{count} members' rights have been restored."
else
  puts "Error: 'Verified' badge could not be found in the database!"
end

```

## License

MIT

***