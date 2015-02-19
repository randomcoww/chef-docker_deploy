module DockerWrapper

  class DockerError < StandardError; end

  class InspectError < DockerError; end
  class PullError < DockerError; end
  class PushError < DockerError; end
  class RmError < DockerError; end
  class BuildError < DockerError; end
  class CreateError < DockerError; end
  class StopError < DockerError; end

  require 'time'

  def docker_inspect(name)
    return JSON.parse(`docker inspect #{name}`)
  rescue
    raise InspectError
  end

  def docker_pull(name)
    system(%Q{docker pull #{name}})
    raise PullError unless $?.success?
  end

  def docker_push(name)
    system(%Q{docker push #{name}})
    raise PushError unless $?.success?
  end

  def docker_rm(name)
    system(%Q{docker rm #{name}})
    raise RmError unless $?.success?
  end

  def docker_rmi(name)
    system(%Q{docker rm #{name}})
    raise RmiError unless $?.success?
  end

  def docker_build(opts, path)
    system(%Q{docker build #{opts} #{path}})
    raise BuildError unless $?.success?
  end

  def docker_create(opts, image)
    system(%Q{docker create #{opts} #{image}})
    raise CreateError unless $?.success?
  end

  def get_exists?(name)
    system(%Q{docker inspect #{name}})
    return $?.success?
  end

  def get_id(name)
    return docker_inspect(name)['Id']
  end


  def get_container_image_id(name)
    return docker_inspect(name)['Image']
  end

  def get_container_hostname(name)
    return docker_inspect(name)['Config']['Hostname']
  end

  def get_container_running?(name)
    return docker_inspect(name)['Config']['Running']
  end

  def get_container_id(name)
    return docker_inspect(name)['Id']
  end

  def get_container_name(name)
    return docker_inspect(name)['Name'].gsub(/^\//, '')
  end

  def get_container_create_options(name)
    return docker_inspect(name)['Config'] || {}
  end

  def get_container_start_options(name)
    return docker_inspect(name)['HostConfig'] || {}
  end

  def get_container_finished_at(name)
    time = docker_inspect(name)['State']['FinishedAt']
    return Time.parse(time).strftime('%s').to_i
  rescue InspectError
    return 0
  end

  def get_container_post_bindings(name)
    return docker_inspect(name)['HostConfig']['PortBindings'] || {}
  end

  def list_all_images
    return `docker images --no-trunc -q`.lines || []
  end

  def list_all_containers
    return `docker ps -a --no-trunc -q`.lines || []
  end

  def list_running_containers
    return `docker ps --no-trunc -q`.lines || []
  end
end
