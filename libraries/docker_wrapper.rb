module DockerWrapper

  class DockerPull < StandardError; end
  class DockerBuild < StandardError; end
  class StopContainer < StandardError; end

  require 'time'
  require 'json'

  require 'chef/mixin/shell_out'
  include Chef::Mixin::ShellOut

  def docker_inspect(name)
    out = shell_out!(%Q{docker inspect #{name}})
    return JSON.parse(out.stdout)[0]
  end

  def docker_pull(name)
    out = shell_out!(%Q{docker pull #{name}})
    return out.stdout.chomp
  rescue => e
    raise DockerPull, e.message
  end

  def docker_push(name)
    shell_out!(%Q{docker push #{name}})
  end

  def docker_rm(name)
    shell_out!(%Q{docker rm #{name}})
  end

  def docker_rmi(name)
    shell_out!(%Q{docker rm #{name}})
  end

  def docker_build(opts, path)
    status = system(%Q{docker build #{opts} #{path}})
    raise DockerBuild unless status
  end

  def docker_create(opts, image)
    out = shell_out!(%Q{docker create #{opts} #{image}})
    return out.stdout.chomp
  end

  def docker_start(name)
    shell_out!(%Q{docker start #{name}})
  end

  def docker_stop(name)
    shell_out!(%Q{docker stop #{name}})
  end

  def docker_kill(name)
    shell_out!(%Q{docker kill #{name}})
  end

  def get_exists?(name)
    shell_out!(%Q{docker inspect #{name}})
    return true
  rescue
    return false
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

  def get_container_config(name)
    return docker_inspect(name)['Config'] || {}
  end

  def get_container_hostconfig(name)
    return docker_inspect(name)['HostConfig'] || {}
  end

  def get_container_port_bindings(name)
    return docker_inspect(name)['HostConfig']['PortBindings'] || {}
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
    out = shell_out!(%Q{docker images --no-trunc -q})
    return out.stdout.lines.map { |k| k.chomp } || []
  end

  def list_all_containers
    out = shell_out!(%Q{docker ps -a --no-trunc -q})
    return out.stdout.lines.map { |k| k.chomp } || []
  end

  def list_running_containers
    out = shell_out!(%Q{docker ps --no-trunc -q})
    return out.stdout.lines.map { |k| k.chomp } || []
  end
end