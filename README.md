# discourse-github-stats

Prints a list of all contributors in https://github.com/discourse between to Discourse versions.

Contributions in forked repositores are excluded -- with the exception of the ones [defined in `stats.rb`](https://github.com/gschlager/discourse-github-stats/blob/069f42182eba28d80613d163b92867397e3c909d/stats.rb#L8)

### Usage
```bash
bundle exec stats.rb <start_tag> <end_tag> [--verbose]
```

The `--verbose` options lists the affected repositories for each contributor.

##### Example:
```bash
bundle exec ruby stats.rb v1.9.0 v2.0.0
```
