module DockerDeployHelpers

  require 'tempfile'
  require 'securerandom'

  class ChefRestHelper
    
    def initialize(chef_server_url = nil, chef_admin_user = nil, chef_admin_key = nil)
      @chef_server_url = chef_server_url || Chef::Config[:chef_server_url]
      @chef_admin_user = chef_admin_user || Chef::Config[:node_name]
      @chef_admin_key = chef_admin_key || Chef::Config[:client_key]
    end

    def remove_from_chef(name)
      f = Tempfile.new('chef_key')
      f.write(@chef_admin_key)
      f.close
      
      rest = Chef::REST.new(@chef_server_url, @chef_admin_user, f.path)
      rest.delete_rest(::File.join('clients', name))
      rest.delete_rest(::File.join('nodes', name))
    rescue
    ensure
      f.unlink
    end

    def exists?(name)
      rest = Chef::REST.new(@chef_server_url)

      client = rest.get_rest(::File.join('clients', name)).to_hash
      return !client.empty?

    rescue Net::HTTPServerException
      return false
    end
  end

  def set_docker_api_timeout(t)
    Excon.defaults[:write_timeout] = t
    Excon.defaults[:read_timeout] = t
  end

  def generate_unique_container_name(base_name)
    return "#{base_name}-#{SecureRandom.hex(6)}"
  end

  ## ugly hack to install gem prereqs for docker library
  ## http://stackoverflow.com/questions/9236673/ruby-gems-in-stand-alone-ruby-scripts
  def require_gem(name, version = nil, install_name = nil)
    require 'rubygems'

    begin
      require name

    rescue LoadError
      install_name = name if install_name.nil?
      version = "--version '#{version}'" unless version.nil?
      gem_bin = File.join(RbConfig::CONFIG['bindir'], 'gem')
      
      system("#{gem_bin} install #{install_name} #{version}")
      Gem.clear_paths
    
      retry
    end
  end
end
