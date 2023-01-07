#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"

  gem "colored2"
  gem "faraday-retry"
  gem "octokit"
  gem "tty-prompt"
end

require "date"
require "optparse"

class GitHubStats
  ORG_NAME = "discourse"
  MAIN_REPO = "discourse/discourse"
  INCLUDED_FORKS = %w[discourse-akismet discourse-signatures discourse-sitemap]

  IGNORED_USERNAMES = %w{dependabot[bot] discourse-translator-bot github-actions[bot]}

  STAFF_UNTIL = {
    "riking" => "2021-07-14",
    "eviltrout" => "2022-04-11",
    "udan11" => "2022-04-11",
    "markvanlan" => "2022-04-25",
    "justindirose" => "2022-05-17",
    "hnb-ku" => "2022-09-15",
    "scossar" => "2022-09-15",
    "frank3manuel" => "2022-11-02",
  }

  def initialize(options)
    token =
      if options[:token]
        options[:token]
      else
        prompt = TTY::Prompt.new
        prompt.say (<<~TIP).green
          You need a GitHub Personal Access Token with 'read:org' scope to run this script.
          You can create a classic token at https://github.com/settings/tokens/new
        TIP

        prompt.mask("GitHub Personal Access Token:")
      end

    @client = Octokit::Client.new(access_token: token)

    @verbose = options[:verbose]
    @start_tag_name = options[:start_tag]
    @end_tag_name = options[:end_tag]

    STAFF_UNTIL.transform_values! { |value| DateTime.parse(value).to_time }
  end

  def calculate
    puts "Calculating start and end date..."
    start_date, end_date = find_start_end_dates
    puts "Counting contributions between #{start_date.iso8601} and #{end_date.iso8601}"

    puts "Reading org members..."
    org_members = member_names

    contributors = find_contributors(start_date, end_date, org_members)

    puts "\n\nContributors (#{contributors.length}):"
    contributors.each { |name, contributor| puts format_contributor(name, contributor) }
  rescue StandardError => e
    STDERR.puts e.message
    exit(1)
  end

  private

  def find_start_end_dates
    start_tag = end_tag = nil
    tags = @client.tags(MAIN_REPO)
    last_response = @client.last_response

    loop do
      start_tag = tags.find { |tag| tag.name == @start_tag_name } if start_tag.nil?

      end_tag = tags.find { |tag| tag.name == @end_tag_name } if @end_tag_name && end_tag.nil?

      break if (start_tag && (!@end_tag_name || end_tag)) || last_response.rels[:next].nil?

      last_response = last_response.rels[:next].get
      tags = last_response.data
    end

    raise "Could not find start tag #{@start_tag_name}" if start_tag.nil?
    raise "Could not find end tag #{@end_tag_name}" if @end_tag_name && end_tag.nil?

    start_date = commit_date(start_tag)
    end_date = @end_tag_name ? commit_date(end_tag) : Time.now.utc
    [start_date, end_date]
  end

  def commit_date(tag)
    commit = tag.commit.rels[:self].get.data
    commit.commit.committer.date
  end

  def repositories(start_date)
    repositories = @client.org_repositories(ORG_NAME, type: :public)
    last_response = @client.last_response

    while last_response.rels[:next]
      last_response = last_response.rels[:next].get
      repositories.concat(last_response.data)
    end

    repositories.select { |repo| repo.pushed_at >= start_date }
  end

  def member_names
    members = @client.org_members(ORG_NAME)
    last_response = @client.last_response

    while last_response.rels[:next]
      last_response = last_response.rels[:next].get
      members.concat(last_response.data)
    end

    members.map { |m| m.login }.to_set
  end

  def find_contributors(start_date, end_date, org_members)
    contributors = {}
    ignored_repositories = []

    repositories(start_date).each do |repo|
      if repo.fork && !INCLUDED_FORKS.include?(repo.name)
        ignored_repositories << repo.name
      else
        puts "Reading commits for #{repo.full_name}..."
        add_contributors(contributors, repo.full_name, start_date, end_date)
      end
    end

    puts "", "Ignored repositories: ", ignored_repositories unless ignored_repositories.empty?

    contributors
      .reject { |name| org_members.include?(name) }
      .sort_by { |name, contributions| [contributions[:count], name] }
      .reverse
  end

  def add_contributors(contributors, repo, start_date, end_date)
    commits = @client.commits_between(repo, start_date, end_date, per_page: 100)
    last_response = @client.last_response

    loop do
      commits.each do |commit|
        author = commit.author&.login || commit.commit.author.name

        next if IGNORED_USERNAMES.include?(author)
        next if was_staff_at_time_of_commit?(author, commit)

        if contributors.has_key?(author)
          contributors[author][:count] += 1
        else
          contributors[author] = { count: 1, url: commit.author&.html_url, repos: {} }
        end

        if contributors[author][:repos].has_key?(repo)
          contributors[author][:repos][repo] += 1
        else
          contributors[author][:repos][repo] = 1
        end
      end

      break if last_response.rels[:next].nil?

      last_response = last_response.rels[:next].get
      commits = last_response.data
    end
  end

  def was_staff_at_time_of_commit?(author, commit)
    STAFF_UNTIL.has_key?(author) && commit.commit.author.date < STAFF_UNTIL[author]
  end

  def format_contributor(name, contributor)
    count = contributor[:count].to_s.rjust(3, " ")
    url = contributor[:url]

    text = url ? "#{count} [#{name}](#{url})" : "#{count} #{name}"

    if @verbose
      repos = contributor[:repos].sort_by { |_, count| count }.reverse
      text << " (#{repos.inspect})"
    end

    text
  end
end

def parse_options
  options = {}
  parser =
    OptionParser.new do |opts|
      opts.banner =
        "Usage: #{File.basename($0)} --start-tag TAG [--end-tag TAG] [--verbose] [--token TOKEN]"

      opts.on(
        "-s TAG",
        "--start-tag TAG",
        "The git tag used to calculate the start date",
      ) { |value| options[:start_tag] = value }

      opts.on("-e TAG", "--end-tag TAG", "The git tag used to calculate the end date") do |value|
        options[:end_tag] = value
      end

      opts.on("-v", "--verbose", "Run verbosely") { |value| options[:verbose] = value }

      opts.on("-t TOKEN", "--token TOKEN", "GitHub Personal Access Token") do |value|
        options[:token] = value
      end

      opts.on("-h", "--help", "Print usage") do
        puts opts
        exit
      end
    end
  parser.parse!

  unless options.keys.include?(:start_tag)
    puts parser.help
    exit 1
  end

  options
end

GitHubStats.new(parse_options).calculate
