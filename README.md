```python
import pandas as pd

try:
    df_history = pd.read_csv("Discourse_Developer_Guides_and_Source_References.csv")
    print("History file loaded. Columns:", df_history.columns.tolist())
    print(df_history.head(2))
except Exception as e:
    print(f"Error loading history file: {e}")
    
try:
    df_table = pd.read_csv("Discourse_Developer_Guides_and_Table_1.csv")
    print("\nTable file loaded. Columns:", df_table.columns.tolist())
    print(df_table.head(2))
except Exception as e:
    print(f"Error loading table file: {e}")

```

```text
History file loaded. Columns: ['Index', 'Reference']
   Index                                                                  Reference
0      1                 Run Discourse AI evals - Developer Guides - Discourse Meta
1      2  Controlling site settings with themes - Developer Guides - Discourse Meta

Table file loaded. Columns: ['Guide Title', 'Category', 'Primary Topic', 'Technical Focus', 'Prerequisites/Requirements', 'Key Instructions', 'Last Reviewed/Updated', 'Source']
                             Guide Title                        Category  Primary Topic             Technical Focus                                                                       Prerequisites/Requirements                                                                                                                                       Key Instructions Last Reviewed/Updated Source
0                 Run Discourse AI evals  Documentation Developer Guides             ai        Ruby CLI, LLMs, YAML  Working development environment with Discourse AI plugin; API keys for OpenAI/Anthropic/Gemini.  Navigate to plugins/discourse-ai/evals; run 'bundle exec ruby ./run --help'; use --list-features to find behaviors; run single eval or compare modes.      December 1, 2025      1
1  Controlling site settings with themes  Documentation Developer Guides  Not in source  JSON, siteSettings service                                   Setting must be marked as 'themeable: true' in Discourse core.                                                Add theme_site_settings section to about.json; define the core setting name and the new override value.         July 16, 2025      2


```

Discourse ve GitHub standartlarına (Adım 15: Dokümantasyon ve Yayınlama) uygun, global açık kaynak topluluğu için tamamen İngilizceye çevrilmiş ve yapılandırılmış `README.md` dosyan aşağıdadır.

Ruby betiğindeki konsol çıktıları (`puts`) ve yorum satırları da uluslararası standartları korumak adına İngilizceye uyarlanmıştır.

---

```markdown
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