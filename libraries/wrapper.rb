module DockerWrapper

  class DockerPull < StandardError; end
  class DockerBuild < StandardError; end
  class DockerCreate < StandardError; end

  class DockerWrapper

    require 'json'
    require 'time'

    require 'chef/mixin/shell_out'
    include Chef::Mixin::ShellOut

    attr_reader :id

    def initialize(ref)
      @id = shell_out!(%Q{docker inspect --format='{{.Id}}' #{ref}})
    end

    def exsists?
      shell_out!(%Q{docker inspect --format='{{.Id}}' #{@id}})
      return true
    rescue
      return false
    end

    def inspect
      out = shell_out!(%Q{docker inspect #{@id}})
      return JSON.parse(out.stdout)[0]
    end

    class << self
      def get(name)
         return new(name)
      end
    end

    class Image < DockerWrapper

      def rmi
        shell_out!(%Q{docker rmi #{@id}})
      end

      def push
        shell_out!(%Q{docker push #{@id}})
      end

      class << self

        def pull(name)
          puts "Running: docker pull #{name}"

          out = shell_out!(%Q{docker pull #{name}})
          id = out.stdout.chomp
          return new(id)
        rescue => e
          raise DockerPull, e.message
        end

        def build(name, opts, path)
          puts "Running: docker build -t #{name} #{opts} #{path}"

          status = system(%Q{docker build -t #{name} #{opts} #{path}})
          raise DockerBuild unless status
          return new(name)
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
        return inspect(@id)['Config'] || {}
      end

      def hostconfig
        return inspect(@id)['HostConfig'] || {}
      end

      def finished_at
        out = shell_out!(%Q{docker inspect --format='{{.State.FinishedAt}}' #{@id}})
        return Time.parse(out.stdout.chomp).strftime('%s').to_i
      rescue
        return 0
      end

      def dynamic_volumes
        volumes = inspect(@id)['Config']['Volumes'] || {}
        volumes.keys.map { |k|
          volumes[k] = inspect(@id)['Volumes'][k]
        }
        return volumes
      end

      def cleanup
        image = DockerWrapper::Image.new(parent_id)

        rm
        kill if running?

        image.rmi
      rescue
      end

      class << self

        def create(opts, image)
          puts "Running: docker create #{opts} #{image}"

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
end
