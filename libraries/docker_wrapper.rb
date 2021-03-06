require 'json'
require 'time'
require 'securerandom'
require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

module DockerHelper

  class DockerPull < StandardError; end
  class DockerBuild < StandardError; end
  class DockerCreate < StandardError; end
  class DockerGet < StandardError; end
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
        raise DockerGet, e.message
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

      def read_file(file)
        out = shell_out!(%Q{docker run --rm=true --entrypoint="cat" #{@id} #{file}})
        return out.stdout.chomp
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

      def labels
        out = shell_out!(%Q{docker inspect --format='{{json .Config.Labels}}' #{@id}})
        return JSON.parse(out.stdout.chomp)
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

      def rename(new_name)
        shell_out!(%Q{docker rename #{name} #{new_name}}) unless name == new_name
      end

      class << self

        def create(opts, image, command)
          out = shell_out!(%Q{docker create #{opts} #{image} #{command}})
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
end
