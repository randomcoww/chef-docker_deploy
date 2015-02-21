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
    shell_out!(%Q{docker rmi #{name}})
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
    shell_out!(%Q{docker inspect --format='{{.Id}}' #{name}})
    return true
  rescue
    return false
  end

  def get_id(name)
    out = shell_out!(%Q{docker inspect --format='{{.Id}}' #{name}}).chomp
    return out.stdout.chomp
  end


  def get_container_image_id(name)
    out = shell_out!(%Q{docker inspect --format='{{.Image}}' #{name}}).chomp
    return out.stdout.chomp
  end

  def get_container_hostname(name)
    out = shell_out!(%Q{docker inspect --format='{{.Config.Hostname}}' #{name}}).chomp
    return out.stdout.chomp
  end

  def get_container_running?(name)
    out = shell_out!(%Q{docker inspect --format='{{.State.Running}}' #{name}}).chomp
    return out.stdout.chomp == 'true'
  end

  def get_container_name(name)
    out = shell_out!(%Q{docker inspect --format='{{.Name}}' #{name}}).gsub(/^\//, '')
    return out.stdout.chomp
  end

  def get_container_config(name)
    return docker_inspect(name)['Config'] || {}
  end

  def get_container_hostconfig(name)
    return docker_inspect(name)['HostConfig'] || {}
  end

  def get_container_finished_at(name)
    out = shell_out!(%Q{docker inspect --format='{{.State.FinishedAt}}' #{name}}).chomp
    time = out.stdout.chomp
    return Time.parse(time).strftime('%s').to_i
  rescue
    return 0
  end

  def get_container_docker_volumes(name)
    
    volumes = docker_inspect(name)['Config']['Volumes'] || {}
    volumes.keys.map { |k|
      volumes[k] = docker_inspect(name)['Volumes'][k]
    }
    return volumes
  end


  def list_all_images
    out = shell_out!(%Q{docker images --no-trunc -q})
    return out.stdout.lines.map { |k| k.chomp } || []
  end

  def list_dangling_images
    out = shell_out!(%Q{docker images --no-trunc -q -f dangling=true})
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
