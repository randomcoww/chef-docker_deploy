require 'tempfile'
require 'chef/mixin/shell_out'
include Chef::Mixin::ShellOut

module DockerHelper

  def remove_from_chef(chef_server_url, client, keyfile)
    rest = Chef::REST.new(chef_server_url, client, keyfile)
    rest.delete_rest("nodes/#{client}")
    rest.delete_rest("clients/#{client}")

    Chef::Log.info("Removed chef entries for #{@client}")
  rescue => e
    Chef::Log.info("Failed to Remove chef entries for #{@client}: #{e.message}")
  end

  def chef_client_valid(chef_server_url, client, keyfile)
    rest = Chef::REST.new(chef_server_url, client, keyfile)
    rest.get_rest("clients/#{client}")

    return true
  rescue
    return false
  end

  ##
  ## temporarily write key to file for functions that require a file 
  ##

  def write_tmp_key(key)
    t = Tempfile.new('tmpkey')
    t.write(key || '')
    t.close

    yield t.path
  ensure
    t.unlink unless t.nil?
  end

  ##
  ## get chef server - only works using same chef server as docker that of docker node
  ##

  def chef_server_url
    Chef::Config[:chef_server_url]
  end

  ##
  ## try to remove image and warn if in use
  ##

  def remove_unused_image(image)
    image.rmi
  rescue
    Chef::Log.warn("Not removing image in use #{image.id}")
  end

  ##
  ## try to remove all dangling images
  ##

  def cleanup_dangling_images
    DockerWrapper::Image.all('-a -f dangling=true').each do |i|
      remove_unused_image(i)
    end
  end

  ##
  ## stop container, try killing
  ##

  def stop_container(container)
    Chef::Log.info("Stopping container #{container.id}...")
    container.stop
    container.kill if container.running?
    raise StopContainer, "Unable to stop container #{container.name}" if container.running?
  end

  ##
  ## stop and remove container
  ##

  def remove_container(container)
    image = DockerWrapper::Image.new(container.parent_id)
    stop_container(container)

    container.rm
    begin
      Chef::Log.info("Removing image #{image.id}...")
      image.rmi
    rescue
      Chef::Log.info("Not removing image in use #{image.id}")
    end
  end

  ##
  ## sort and compare hash/array
  ##

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
