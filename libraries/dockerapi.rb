include DockerDeploy
include DockerDeploy::Error

require_gem("docker", nil, "docker-api")

require 'time'

Excon.defaults[:write_timeout] = 1800
Excon.defaults[:read_timeout] = 1800

## add some functions to docker api

class Docker::Image
  def image_id
    return json['Id']
  end

  def remove_non_active(opts = {})
    remove(opts)
  rescue Excon::Errors::Conflict
    #
  end

  def tag_if_untagged(opts = {})
    tag(opts)
  rescue Excon::Errors::Conflict
    #
  end

  class << self
    def get_local(id, opts = {}, conn = Docker.connection)
      get(id, opts, conn)
    rescue => e
      raise DockerDeploy::Error::GetImageError, "Could not get image #{id}: #{e.message}"
    end

    def pull(opts = {}, creds = nil, conn = Docker.connection)
      create(opts, creds, conn)
    rescue => e
      raise DockerDeploy::Error::PullImageError, "Error pulling image #{[opts['fromImage'], opts['tag']].join(':')}: #{e.message}"
    end

    def build_and_tag(name, tag, dir, opts = {})
      image = build_from_dir(dir, opts, Docker.connection, nil) do |out|
        out.gsub(/^{"stream":"(.*?)"}/) {
          $1.split('\n').map { |s| puts s }
        }
      end

      image.tag_if_untagged('repo' => name, 'tag' => tag) if (image)
    rescue => e
      image.remove_non_active if (image)
      raise DockerDeploy::Error::BuildImageError, "Error building image #{name}:#{tag}: #{e.message}"
    end

  end
end

class Docker::Container
  def name
    json['Name'].gsub(/^\//, '')
  end

  def container_id
    json['Id']
  end

  def image_id
    json['Image']
  end

  def hostname
    json['Config']['Hostname']
  end
 
  def running?
    json['State']['Running']
  end

  def create_options
    json['Config'] || {}
  end
  
  def start_options
    json['HostConfig'] || {}
  end
 
  def port_bindings
    json['HostConfig']['PortBindings'] || {}
  end

  def finished_at_time
    time = json['State']['FinishedAt']
    if (time)
      return Time.parse(time).strftime('%s').to_i
    end

    return 0
  end
  
  class << self

    def exist?(id, opts = {}, conn = Docker.connection)
      get(id, opts, conn)
      true
    rescue Docker::Error::NotFoundError
      false
    end
  end
end
