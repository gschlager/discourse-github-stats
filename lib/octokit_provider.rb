require "octokit"
require "io/console"

class OctokitProvider
  def self.create
    OctokitProvider.new.create_client
  end

  def create_client
    Octokit::Client.new(access_token: github_oauth_token)
  end

  private

  def github_oauth_token
    if File.exists?(github_oauth_token_file)
      File.read(github_oauth_token_file)
    else
      new_github_oauth_token
    end
  end

  def new_github_oauth_token
    puts "Requesting a new OAuth token from Github..."
    print "Github username: "
    user = $stdin.gets.chomp
    print "Github password: "
    pass = $stdin.noecho(&:gets).chomp

    api = Octokit::Client.new(login: user, password: pass)

    begin
      api.user
    rescue Octokit::OneTimePasswordRequired
      print "\nGithub 2FA token: "
      token = $stdin.gets.chomp
    end

    begin
      note = "Discourse stats script"
      options = { note: note, scopes: ["read:org"] }

      options.merge!(headers: { "X-GitHub-OTP" => token }) if token

      api
        .authorizations(options)
        .find do |authorization|
          if authorization[:app][:name] == note
            api.delete_authorization(authorization[:id], options)
          end
        end

      res = api.create_authorization(options)
    rescue Octokit::OneTimePasswordRequired
      STDERR.puts "\n2FA token incorrect. Please try again.\n\n"
      return new_github_oauth_token
    end

    res[:token].tap do |token|
      FileUtils.mkpath(ENV["HOME"] + "/.discourse")
      File.write(github_oauth_token_file, token)
    end
  rescue Octokit::Unauthorized
    STDERR.puts "\nUsername or password incorrect. Please try again.\n\n"
    return new_github_oauth_token
  end

  def github_oauth_token_file
    ENV["HOME"] + "/.discourse/github_stats_oauth_token"
  end
end
