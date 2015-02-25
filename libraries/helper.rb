require 'tempfile'
require 'securerandom'
require 'json'
require 'time'
require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

module DockerHelper

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

  def compare_config(a, b)
    return sort_config(a) == sort_config(b)
  end

  class DockerPull < StandardError; end
  class DockerBuild < StandardError; end
  class DockerCreate < StandardError; end
  class DockerGetImage < StandardError; end
  class DockerPush < StandardError; end
  class NotFound < StandardError; end

  class DockerWrapper

    attr_reader :id

    def initialize(id)
      @id = id
    end

    def inspect
      out = shell_out!(%Q{docker inspect #{@id}})
      return JSON.parse(out.stdout)[0]
    end

    def ==(obj)
      return id == obj.id
    end

    def !=(obj)
      return id != obj.id
    end

    class << self
      def new_with_name(name)
        out = shell_out!(%Q{docker inspect --format='{{.Id}}' #{name}})
        return new(out.stdout.chomp)
      rescue => e
        raise NotFound, e.message
      end

      def get(name)
        return new_with_name(name)
      rescue => e
        raise DockerGetImage, e.message
      end

      def exists?(name)
        shell_out!(%Q{docker inspect --format='{{.Id}}' #{name}})
        return true
      rescue
        return false
      end
    end

    class Image < DockerWrapper

      def rmi
        shell_out!(%Q{docker rmi #{@id}})
      end

      def push
        status = system(%Q{docker push #{@id}})
        raise DockerPush unless status
      end

      class << self

        def pull(name)
          status = system(%Q{docker pull #{name}})
          raise DockerPull unless status
          return new_with_name(name)
        end

        def build(name, opts, path)
          status = system(%Q{docker build #{opts} --tag="#{name}" #{path}})
          raise DockerBuild unless status
          return new_with_name(name)
        end

        def all(opts)
          out = shell_out!(%Q{docker images --no-trunc -q #{opts}})
          return out.stdout.lines.map { |k| new(k.chomp) } || []
        end
      end
    end

    class Container < DockerWrapper

      def rm
        shell_out!(%Q{docker rm #{@id}})
      end

      def start
        shell_out!(%Q{docker start #{@id}})
      end

      def stop
        shell_out!(%Q{docker stop #{@id}})
      end

      def kill
        shell_out!(%Q{docker kill #{@id}})
      end

      def parent_id
        out = shell_out!(%Q{docker inspect --format='{{.Image}}' #{@id}})
        return out.stdout.chomp
      end

      def hostname
        out = shell_out!(%Q{docker inspect --format='{{.Config.Hostname}}' #{@id}})
        return out.stdout.chomp
      end

      def running?
        out = shell_out!(%Q{docker inspect --format='{{.State.Running}}' #{@id}})
        return out.stdout.chomp == 'true'
      rescue
        return false
      end

      def name
        out = shell_out!(%Q{docker inspect --format='{{.Name}}' #{@id}}).gsub(/^\//, '')
        return out.stdout.chomp
      end

      def config
        return inspect['Config'] || {}
      end

      def hostconfig
        return inspect['HostConfig'] || {}
      end

      def finished_at
        out = shell_out!(%Q{docker inspect --format='{{.State.FinishedAt}}' #{@id}})
        return Time.parse(out.stdout.chomp).strftime('%s').to_i
      rescue
        return 0
      end

      def dynamic_volumes
        volumes = inspect['Config']['Volumes'] || {}
        volumes.keys.map { |k|
          volumes[k] = inspect['Volumes'][k]
        }
        return volumes
      end

      class << self

        def create(opts, image)
          out = shell_out!(%Q{docker create #{opts} #{image}})
          id =  out.stdout.chomp
          return new(id)
        rescue => e
          raise DockerCreate, e.message
        end

        def all(opts)
          out = shell_out!(%Q{docker ps --no-trunc -q #{opts}})
          return out.stdout.lines.map { |k| new(k.chomp) } || []
        end
      end
    end
  end

  private

  def sort_config(c)
    return sort_hash(c) if c.is_a?(Hash)
    return sort_array(c) if c.is_a?(Array)
    return c
  end

  def sort_hash(h)
    h.map { |k, v|
      if v.is_a?(Hash)
        h[k] = sort_hash(v)
      elsif v.is_a?(Array)
        h[k] = sort_array(v)
      end
    }

    ## no need to sort hash
    #return Hash[h.sort]
    return h
  end

  def sort_array(a)
    a.map { |v|
      if v.is_a?(Hash)
        sort_hash(v)
      elsif v.is_a?(Array)
        sort_array(v)
      end
    }

    return a.sort{ |a, b| a.to_s <=> b.to_s }
  end
end
