require 'json';
require 'forwardable';

# http://stackoverflow.com/a/30225093 - except using refinements
module DeepHashMerge
  refine Hash do
    def deep_merge(second)
      merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2 }
      self.merge(second.to_h, &merger)
    end
  end
end

configuration = {}

class ConfigurationReader
  using DeepHashMerge

  def initialize(directory = "/config")
    @directory = directory
  end

  def read
    Dir[glob_pattern]
      .sort
      .map(&method(:parse))
      .inject({}) { |memo, obj| memo.deep_merge(obj) }
      #.inject(&:deep_merge) this does not work for some reason: in `each': super: no superclass method `deep_merge' for #<Hash:0x0055628981cae0> (NoMethodError)
  end

  private

  def glob_pattern
    File.join(@directory, "*.json")
  end

  def parse(file)
    JSON.parse(IO.read(file))
  end
end

class Configuration
  extend Forwardable

  def_delegators :@data, :fetch

  def initialize(data, additional_config)
    @data = data.merge(additional_config)
  end

  def inspect
    JSON.pretty_generate @data
  end
end

class DovecotGenerator
  def initialize(config)
    @config = config
  end

  def generate
    @config.fetch("mx", {}).map do |domain, domain_config|
      domain_config.fetch("accounts", {}).map do |username, account_config|
        generate_account(domain, username, account_config["password"])
      end
    end.join("\n")
  end

  private

  def generate_account(domain, username, password)
    "#{username}@#{domain}:#{password}"
  end
end

class PostfixAliases
  def initialize(config)
    @config = config
  end

  def generate
    @config.fetch("mx", {}).map do |domain, domain_config|
      domain_config.fetch("aliases", {}).map do |username, alias_config|
        generate_alias(domain, username, alias_config["destination"])
      end
    end.join("\n")
  end

  private

  def generate_alias(domain, username, destination)
    "#{username}@#{domain}  #{destination}"
  end
end

class PostfixDomains
  def initialize(config)
    @config = config
  end

  def generate
    @config.fetch("mx", {}).keys.join("\n")
  end
end

class PostfixControlledEnvelopeSenders
  def initialize(config)
    @config = config
  end

  def generate
    @config.fetch("mx", {}).map do |domain, domain_config|
      domain_config.fetch("accounts", {}).map do |username, account_config|
        generate_account(domain, username)
      end
    end.join("\n")
  end

  private

  def generate_account(domain, username)
    "#{username}@#{domain} #{username}@#{domain}"
  end
end

class OpenDKIM
  def initialize(config, owner: 0, group: 0)
    @config = config
    @owner = owner
    @group = group
  end

  def generate
    old = Dir.pwd

    Dir.chdir(@config.fetch('root_directory'))

    exists? 'keys'

    Dir.chdir 'keys'

    @config.fetch("mx", {}).each do |domain, domain_config|
      unless exists? domain
        Dir.chdir domain

        system("opendkim-genkey -r -d #{domain} --verbose")
        puts Dir.pwd
        File.chown(@owner, @group, "default.private", "default.txt")
        File.chmod(0600, "default.private", "default.txt")

        Dir.chdir '..'
      end
    end

    Dir.chdir old

    nil
  end

  private

  def exists?(*parts)
    path = File.join *parts

    if Dir.exist? path
      true
    else
      Dir.mkdir path
      false
    end
  end
end

class OpenDKIMKeyTable
  def initialize(config)
    @config = config
  end

  def generate
    @config.fetch("mx", {}).keys.map do |domain|
      "default._domainkey.#{domain} #{domain}:default:/config/keys/#{domain}/default.private"
    end.join("\n")
  end
end

class OpenDKIMSigningTable
  def initialize(config)
    @config = config
  end

  def generate
    @config.fetch("mx", {}).keys.map do |domain|
      "*@#{domain} default._domainkey.#{domain}"
    end.join("\n")
  end
end

class OpenDKIMTrustedHosts
  def initialize(config)
    @config = config
  end

  def generate
    (%w(127.0.0.1 localhost) + @config.fetch("mx", {}).keys).join("\n")
  end
end

class OutputFileWriter
  def initialize(config, filename, chmod: 0644, owner: nil, group: nil)
    @root_directory = config.fetch("root_directory")
    @filename = filename
    @chmod = chmod
    @owner = owner
    @group = group
  end

  def <<(new_content)
    if new_content != current_content
      IO.write(filename, new_content)
      File.chmod(@chmod, filename)
      File.chown(@owner, @group, filename)
      puts "#{filename} updated"
      true
    else
      puts "#{filename} was not updated"
      false
    end
  end

  private

  def current_content
    IO.read(filename)
  rescue Errno::ENOENT
    nil
  end

  def filename
    File.join(@root_directory, @filename)
  end
end

class OutputPostfixHashWriter < OutputFileWriter
  def <<(new_content)
    if super
      system("postmap /config/#{@filename}")
    end
  end
end

class Generator
  USER_DOVECOT = 105
  GROUP_DOVECOT = 109
  USER_OPENDKIM = 109
  GROUP_OPENDKIM = 114
  def self.run
    new.run
  end

  def run
    OutputFileWriter.new(config, "dovecot-passwd", owner: USER_DOVECOT, group: GROUP_DOVECOT ) << DovecotGenerator.new(config).generate
    OutputPostfixHashWriter.new(config, "postfix-aliases") << PostfixAliases.new(config).generate
    OutputFileWriter.new(config, "postfix-domains") << PostfixDomains.new(config).generate
    OutputPostfixHashWriter.new(config, "postfix-controlled-envelope-senders") << PostfixControlledEnvelopeSenders.new(config).generate
    OpenDKIM.new(config, owner: USER_OPENDKIM, group: GROUP_OPENDKIM).generate
    OutputFileWriter.new(config, "opendkim-keytable", owner: USER_OPENDKIM, group: GROUP_OPENDKIM) << OpenDKIMKeyTable.new(config).generate
    OutputFileWriter.new(config, "opendkim-signingtable", owner: USER_OPENDKIM, group: GROUP_OPENDKIM) << OpenDKIMSigningTable.new(config).generate
    OutputFileWriter.new(config, "opendkim-trustedhosts", owner: USER_OPENDKIM, group: GROUP_OPENDKIM) << OpenDKIMTrustedHosts.new(config).generate
  end

  private

  def config
    @config ||= Configuration.new(ConfigurationReader.new("/source").read, "root_directory" => (ARGV[0] || Dir.pwd))
  end

end

Generator.run
