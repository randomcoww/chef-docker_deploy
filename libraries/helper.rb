require 'tempfile'
require 'json'
require 'time'
require 'securerandom'
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
