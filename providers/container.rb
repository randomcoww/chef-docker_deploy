class Chef::Provider
  include DockerDeploy
  include DockerDeploy::Error
end

def whyrun_supported?
  true
end

def load_current_resource
  @current_resource = Chef::Resource::DockerDeployContainer.new(new_resource.name)
  @current_resource.exists = Docker::Container.exist?(new_resource.name)

  @rest = ChefRestHelper.new(new_resource.chef_server_url)
  @current_resource
end

def set_resources
  image = Docker::Image.get_local("#{new_resource.base_image}:#{new_resource.base_image_tag}")

  new_resource.node_name(new_resource.name) unless (new_resource.node_name)
  new_resource.chef_secure_dir(::File.join(Chef::Config[:cache_path], new_resource.node_name)) unless (new_resource.chef_secure_dir)

  ## combine all create options
  @container_create_options = new_resource.container_create_options.merge({
    "Hostname" => new_resource.node_name,
    "Env" => new_resource.env.to_a | ["CHEF_NODE_NAME=#{new_resource.node_name}"],
    #"Image" => "#{new_resource.base_image}:#{new_resource.base_image_tag}",
    "Image" => image.image_id,
  })
  ## combine all start options
  @container_start_options = new_resource.container_start_options.merge({
    "Binds" => new_resource.binds.to_a | ["#{new_resource.chef_secure_dir}:/etc/chef/secure"],
    "PortBindings" => new_resource.port_bindings,
  })
end

def create_container
  container = Docker::Container.create(@container_create_options.merge( "name" => new_resource.name ))
  @container_create_options = container.create_options
  @container_start_options = container.start_options.merge( @container_start_options )

  return container
end  

def create_unique_container
  container = Docker::Container.create(@container_create_options.merge( "name" => generate_unique_container_name(new_resource.name) ))
  @container_create_options = container.create_options
  @container_start_options = container.start_options.merge( @container_start_options )

  return container
end

def start_container(container)
  stop_conflicting_containers(container) if new_resource.stop_conflicting
  populate_secure_dir unless @rest.exists?(new_resource.node_name)
  container.start(@container_start_options)
end

def stop_container(container)
  container.stop if container.running?
  container.kill if container.running?
  if (container.running?)
    raise DockerDeploy::Error::StopContainerError, "Unable to stop container #{container.container_id}"
  end
end

def compare_container_config(a, b)
  #puts JSON.pretty_generate(a)
  #puts JSON.pretty_generate(b)
  return a == b
end

def populate_secure_dir
  directory new_resource.chef_secure_dir do
    recursive true
    action :nothing
  end.run_action(:create)

  ## optional
  file ::File.join(new_resource.chef_secure_dir, 'encrypted_data_bag_secret') do
    sensitive true
    content new_resource.encrypted_data_bag_secret
    action :nothing
    not_if { new_resource.encrypted_data_bag_secret.nil? }
  end.run_action(:create)

  file ::File.join(new_resource.chef_secure_dir, 'client.pem') do
    sensitive true
    action :nothing
  end.run_action(:delete)

  file ::File.join(new_resource.chef_secure_dir, 'validation.pem') do
    sensitive true
    content new_resource.validation_key
    action :nothing
  end.run_action(:create)
end

def create_wrapper_scripts(container)
  template "#{new_resource.name}_init_wrapper" do
    path "/etc/init.d/#{new_resource.name}"
    source new_resource.init_template
    cookbook new_resource.init_cookbook
    variables lazy {{
      :actions => {
        'start' => "docker start #{container.container_id}",
        'stop' => "docker stop #{container.container_id}",
        'attach' => "docker exec -it #{container.container_id} /bin/bash",
      }
    }}
    mode 0755
    action :create
  end
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

def stop_conflicting_containers(container)
  host_port_bindings = parse_host_ports(@container_start_options['PortBindings'])

  Docker::Container.all(:all => false).each do |c|
    ## skip self
    next if container.container_id == c.container_id

    parse_host_ports(c.port_bindings).each_key do |p|
      if (host_port_bindings.has_key?(p))
        stop_container(c)
      end
    end
  end
end

def rotate_node_containers(container)
  containers_rotate = {}

  Docker::Container.all(:all => true).each do |c|
    ## look for matching hostname
    next unless new_resource.node_name == c.hostname
    ## skip self
    next if container.container_id == c.container_id

    stop_container(c)
    containers_rotate[c.finished_at_time] = c
  end

  keys = containers_rotate.keys.sort
  while (keys.size >= new_resource.keep_releases)
    c = containers_rotate[keys.shift]
    image_id = c.image_id

    c.remove
    Docker::Image.get_local(image_id).remove_non_active
  end
end

## actions ##

def create_if_missing
  if (@current_resource.exists)
    container = Docker::Container.get(new_resource.name)
    
    unless (container.running?)
      converge_by("Started container #{new_resource.name}") do
        start_container(container)
      end
    end
    return
  end

  converge_by("Created new container #{new_resource.name}") do
    set_resources
    container = create_container(new_resource.name)
    start_container(container) unless (container.running?)
  end
  
  create_wrapper_scripts(container)
end

def create
  set_resources

  if (@current_resource.exists)
    ## do thorough comparison
    container = Docker::Container.get(new_resource.name)
    ## update container_configs
    dummy_container = create_unique_container
    dummy_container.remove
    
    if (compare_container_config(container.create_options, @container_create_options) and
      compare_container_config(container.start_options, @container_start_options))
      
      unless (container.running?)
        converge_by("Started container #{new_resource.name}") do
          start_container(container)
        end
      end
      return
    end

    stop_container(container)
    container.remove
  end

  converge_by("Created new container #{new_resource.name}") do 
    container = create_container
    start_container(container) unless (container.running?)
  end
  
  create_wrapper_scripts(container)
end

def create_and_rotate
  set_resources
  ## create the new container
  container = create_unique_container
  container_id = container.container_id

  ## look for similar containers
  Docker::Container.all(:all => true).each do |c|
    ## found self
    next if (c.container_id == container_id)

    if (compare_container_config(c.create_options, @container_create_options) and
      compare_container_config(c.start_options, @container_start_options))
      
      ## similar container already exists. remove the new one
      container.remove
      container = c
      break
      #return
    end
  end

  rotate_node_containers(container)
  create_wrapper_scripts(container)

  unless container.running?
    converge_by("Started container #{new_resource.name}") do
      start_container(container)
    end
  end
end

action :create_if_missing do
  create_if_missing
end

action :create do
  create
end

action :create_and_rotate do
  create_and_rotate
end
