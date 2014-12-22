class Chef::Provider
  include DockerDeploy
  include DockerDeploy::Error
end

def whyrun_supported?
  true
end

def load_current_resource
  @current_resource = Chef::Resource::DockerDeployImage.new(new_resource.name)
  @current_resource.exists = Docker::Image.exist?("#{new_resource.name}:#{new_resource.tag}")

  @rest = ChefRestHelper.new(new_resource.chef_server_url, new_resource.chef_admin_user, new_resource.chef_admin_key)
  @current_resource
end

def set_build_resources
  new_resource.build_dir(::Dir.mktmpdir) if !new_resource.build_dir
  new_resource.build_node_name(generate_unique_container_name('build')) if !new_resource.build_node_name
end

def populate_chef_build_dir
  directory ::File.join(new_resource.build_dir, 'chef') do
    recursive true
  end.run_action(:create)

  ## client to apply to container
  template ::File.join(new_resource.build_dir, 'chef', 'client.rb') do
    source new_resource.client_template
    variables ({
      :chef_environment => new_resource.chef_environment,
      :validation_client_name => new_resource.validation_client_name,
      :chef_server_url => new_resource.chef_server_url
    })
    cookbook new_resource.client_template_cookbook
    action :nothing
  end.run_action(:create)

  ## build optoins including runlist
  file ::File.join(new_resource.build_dir, 'chef', 'first-boot.json') do
    content ::JSON.pretty_generate( new_resource.first_boot )
    action :nothing
  end.run_action(:create)

  ## secure directory for chef-init
  directory ::File.join(new_resource.build_dir, 'chef', 'secure') do
    recursive true
    action :nothing
  end.run_action(:create)

  file ::File.join(new_resource.build_dir, 'chef', 'secure', 'validation.pem') do
    sensitive true
    content new_resource.validation_key
    action :nothing
  end.run_action(:create)

  file ::File.join(new_resource.build_dir, 'chef', 'secure', 'encrypted_data_bag_secret') do
    sensitive true
    content new_resource.encrypted_data_bag_secret
    action :nothing
  end.run_action(:create)

  ## dockerfile
  template ::File.join(new_resource.build_dir, 'Dockerfile') do
    source new_resource.dockerfile_template
    variables ({
      :base_image_name => new_resource.base_image,
      :base_image_tag => new_resource.base_image_tag,
      :build_node_name => new_resource.build_node_name,
      :docker_build_commands => new_resource.docker_build_commands,
    })
    cookbook new_resource.dockerfile_template_cookbook
    action :nothing
  end.run_action(:create)
end

def build_image
  set_build_resources
  populate_chef_build_dir

  return Docker::Image.build_and_tag(new_resource.name, new_resource.tag, new_resource.build_dir, new_resource.build_options)
ensure
  directory new_resource.build_dir do
    recursive true
    action :delete
    only_if { new_resource.remove_build_dir }
  end

  @rest.remove_from_chef(new_resource.build_node_name)
end

## actions ##

def pull_if_missing
  return if (@current_resource.exists)
  converge_by("Pulled new image #{new_resource.name}:#{new_resource.tag}") do
    Docker::Image.pull('fromImage' => new_resource.name, 'tag' => new_resource.tag)
  end
end

def pull
  converge_by("Updated image #{new_resource.name}:#{new_resource.tag}") do
    if (@current_resource.exists)
      image = Docker::Image.get_local("#{new_resource.name}:#{new_resource.tag}")

      begin
        new_image = Docker::Image.pull('fromImage' => new_resource.name, 'tag' => new_resource.tag)
        return if (image.image_id == new_image.image_id)
        
        image.remove_non_active
      rescue DockerDeploy::Error::PullImageError => e
        Chef::Log.warn(e.message)
      end
    else
      pull_if_missing
    end
  end
end

def try_pull_if_missing
  pull_if_missing
rescue DockerDeploy::Error::PullImageError => e
  Chef::Log.warn(e.message)
end

def try_pull
  pull
rescue DockerDeploy::Error::PullImageError => e
  Chef::Log.warn(e.message)
end

def build_if_missing
  return if (@current_resource.exists)
  converge_by("Built image #{new_resource.name}:#{new_resource.tag}") do
    build_image
  end
end

def build
  converge_by("Built image #{new_resource.name}:#{new_resource.tag}") do
    old_image = Docker::Image.get_local("#{new_resource.name}:#{new_resource.tag}") if @current_resource.exists
    old_image.remove_non_active if (old_image)
    build_image
  end
end

def push
  converge_by("Pushed image #{new_resource.name}:#{new_resource.tag}") do
    image = Docker::Image.get_local("#{new_resource.name}:#{new_resource.tag}")
    image.tag_if_untagged('repo' => new_resource.name, 'tag' => new_resource.tag)
    image.push
  end
end

action :pull_if_missing do
  pull_if_missing
end

action :try_pull_if_missing do
  try_pull_if_missing
end

action :pull do
  pull
end

action :try_pull do
  try_pull
end

action :build_if_missing do
  build_if_missing
end

action :build do
  build
end

action :push do
  push
end
