module DockerHelpers

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

  def generate_unique_container_name(base_name)
    return "#{base_name}-#{SecureRandom.hex(6)}"
  end

  def parse_host_ports(port_bindings)
    host_port_bindings = {}

    if (port_bindings.kind_of?(Hash))
      port_bindings.values.map { |host_ports|
        host_ports.map { |host_port|
          if (host_port.kind_of?(Hash))
            host_port_bindings[host_port['HostPort']] = true
          end
        }
      }
    end

    host_port_bindings
  end


end
