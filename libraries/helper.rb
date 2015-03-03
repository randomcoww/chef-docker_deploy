require 'tempfile'
require 'json'
require 'time'
require 'securerandom'
require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

module DockerHelper

  class ChefRestHelper
    def initialize(chef_server_url, client, key)
      @chef_server_url = chef_server_url
      @client = client
      @key = key
    end

    def auth
      keyfile = nil
      keyfile_path = nil

      unless @key.nil?
        keyfile = Tempfile.new('chefkey')
        keyfile.write(@key)
        keyfile.close

        keyfile_path = keyfile.path
      end

      begin
        yield Chef::REST.new(@chef_server_url, @client, keyfile_path)

      ensure
        keyfile.unlink unless keyfile.nil?
      end
    end

    def remove_from_chef(name)
      if (@client.nil? or @key.nil?)
        Chef::Log.warn('Chef admin credentials missing. Not removing chef node.')
        return
      end

      auth do |a|
        begin
          a.delete_rest("clients/#{name}")
          a.delete_rest("nodes/#{name}")

          Chef::Log.info("Removed chef entries for #{name}")
        rescue => e
          Chef::Log.info("Failed to Remove chef entries for #{name}: #{e.message}")
          ##
        end
      end
    end

    class << self

      ## try looking up own client
      def valid?(*args)
        begin
          new(*args).auth do |a|
          
            a.get_rest("clients/#{@client}")
            return true
          end

        rescue Net::HTTPServerException
          return false
        end
      end
    end
  end

  class DockerPull < StandardError; end
  class DockerBuild < StandardError; end
  class DockerCreate < StandardError; end
  class DockerGetImage < StandardError; end
  class DockerPush < StandardError; end
  class NotFound < StandardError; end

  class DockerWrapper

    attr_reader :id

    def initialize(id, name=nil)
      @id = id
      @name = name
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
        id = out.stdout.chomp
        return new(out.stdout.chomp, name == id ? nil : name)
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
        status = system(%Q{docker push #{name}})
        raise DockerPush unless status
      end

      def name
        return @name unless @name.nil?

        out = shell_out!(%Q{docker images --no-trunc -f dangling=false})
        out.stdout.lines.drop(1).map {|k|
          k.split[0..2].map {|j|
            if (j[2] == @id)
              @name = "#{j[0]}:#{j[1]}"
              break
            end
          }
        }

        return @name
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
        return @name unless @name.nil?

        out = shell_out!(%Q{docker inspect --format='{{.Name}}' #{@id}})
        @name = out.stdout.chomp.gsub(/^\//, '')
        return @name
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

      class << self

        def create(opts, image)
          out = shell_out!(%Q{docker create #{opts} #{image}})
          id =  out.stdout.chomp
          return new(id)
        rescue => e
          raise DockerCreate, e.message
        end

        def unique_name(base_name)
          name = "#{base_name}-#{SecureRandom.hex(6)}"
          while exists?(name)
            name = "#{base_name}-#{SecureRandom.hex(6)}"
          end

          return name
        end

        def all(opts)
          out = shell_out!(%Q{docker ps --no-trunc -q #{opts}})
          return out.stdout.lines.map { |k| new(k.chomp) } || []
        end
      end
    end
  end

  ## misc

  def unpack_cookbook(file, path)
    shell_out!(%Q{tar xf #{file} -C #{path}})
  end

  def compare_config(a, b)
    return sort_config(a) == sort_config(b)
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
