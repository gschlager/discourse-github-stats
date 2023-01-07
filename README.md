# discourse-github-stats

Prints a list of all contributors in https://github.com/discourse between to Discourse versions.

Contributions in forked repositories are excluded -- with the exception of the ones defined in `stats.rb`.
It also contains a list of former team members to exclude them from the contributor list during their time as team member.

### Usage
```bash
stats.rb --start-tag TAG [--end-tag TAG] [--verbose] [--token TOKEN]
```

* The `--end-tag` is optional. If it's missing it will use the current date instead of calculating the date based on the tag.
* The `--verbose` options lists the affected repositories for each contributor.

##### Example:
```bash
./stats.rb --start-tag v2.7.0 --end-tag v2.8.0
./stats.rb --start-tag v2.8.0
```
