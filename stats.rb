#!/usr/bin/ruby
require 'optparse'
require_relative 'lib/octokit_provider'

class GitHubStats
  ORG_NAME = 'discourse'
  MAIN_REPO = 'discourse/discourse'
  INCLUDED_FORKS = ['discourse-akismet', 'discourse-signatures', 'discourse-sitemap']

  def initialize
    @client = OctokitProvider.create
  end

  def calculate(start_tag_name, end_tag_name, verbose = false)
    puts "Calculating start and end date..."
    start_date, end_date = find_start_end_dates(start_tag_name, end_tag_name)

    puts "Reading org members..."
    org_members = member_names

    contributers = find_contributors(start_date, end_date, org_members)

    puts "\n\nContributors (#{contributers.length}):"
    contributers.each do |name, contributor|
      puts format_contributor(name, contributor, verbose)
    end

  rescue StandardError => e
    STDERR.puts e.message
    exit(1)
  end

  private

  def find_start_end_dates(start_tag_name, end_tag_name)
    start_tag = end_tag = nil
    tags = @client.tags(MAIN_REPO)
    last_response = @client.last_response

    loop do
      start_tag = tags.find { |tag| tag.name == start_tag_name } if start_tag.nil?
      end_tag = tags.find { |tag| tag.name == end_tag_name } if end_tag.nil?

      break if (start_tag && end_tag) || last_response.rels[:next].nil?

      last_response = last_response.rels[:next].get
      tags = last_response.data
    end

    raise "Could not find start tag #{start_tag_name}" if start_tag.nil?
    raise "Could not find end tag #{end_tag_name}" if end_tag.nil?

    [commit_date(start_tag), commit_date(end_tag)]
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
    contributers = {}
    ignored_repositories = []

    repositories(start_date).each do |repo|
      if repo.fork && !INCLUDED_FORKS.include?(repo.name)
        ignored_repositories << repo.name
      else
        puts "Reading commits for #{repo.full_name}..."
        add_contributers(contributers, repo.full_name, start_date, end_date)
      end
    end

    unless ignored_repositories.empty?
      puts "", "Ignored repositories: ", ignored_repositories
    end

    contributers
      .reject { |name| org_members.include?(name) }
      .sort_by { |_, contributor| contributor[:count] }
      .reverse
  end

  def add_contributers(contributers, repo, start_date, end_date)
    commits = @client.commits_between(repo, start_date, end_date, per_page: 100)
    last_response = @client.last_response

    loop do
      commits.each do |commit|
        author = commit.author&.login || commit.commit.author.name

        if contributers.has_key?(author)
          contributers[author][:count] += 1
        else
          contributers[author] = { count: 1, url: commit.author&.html_url, repos: {} }
        end

        if contributers[author][:repos].has_key?(repo)
          contributers[author][:repos][repo] += 1
        else
          contributers[author][:repos][repo] = 1
        end
      end

      break if last_response.rels[:next].nil?

      last_response = last_response.rels[:next].get
      commits = last_response.data
    end
  end

  def format_contributor(name, contributor, verbose)
    count = contributor[:count].to_s.rjust(3, ' ')
    url = contributor[:url]

    text = url ? "#{count} [#{name}](#{url})" : "#{count} #{name}"

    if verbose
      repos = contributor[:repos].sort_by { |_, count| count }.reverse
      text << " (#{repos.inspect})"
    end

    text
  end
end

if ARGV.length < 2 || ARGV.length > 3
  puts "Usage: bundle exec #{File.basename($0)} <start_tag> <end_tag> [--verbose]"
  exit 0
end

verbose = ARGV.fetch(2, "") == "--verbose"
GitHubStats.new.calculate(ARGV[0], ARGV[1], verbose)
