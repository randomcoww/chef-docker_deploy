define :docker_run do

  class Chef::Resource
    include DockerHelper

    def project_image_exists
      DockerWrapper::Image.exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}")
    end
  end

  enable = params[:enable_service]
  cache_path = ::File.join(Chef::Config[:cache_path], 'docker_deploy', params[:service_name])

  ## get project specific image (if available)
  docker_deploy_image "#{params[:project_image_name]}_pull" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
    ignore_failure true
    not_if { enable and project_image_exists }
  end

  ## start container
  docker_deploy_container "#{params[:service_name]}_start" do
    service_name "#{node.hostname}-#{params[:service_name]}"
    base_image params[:project_image_name]
    base_image_tag params[:project_image_tag]
    container_base_name params[:service_name]
    container_create_options params[:container_create_options]
    encrypted_data_bag_secret params[:encrypted_data_bag_secret]
    data_bags params[:data_bags]
    validation_key params[:validation_key]
    cache_path cache_path
    keep_releases params[:keep_releases]
    command params[:command]
    action enable ? :create : :remove
    not_if { enable and !project_image_exists }
  end

  ## create startup service and script
  template "#{params[:service_name]}_init" do
    path ::File.join('/etc', 'init.d', params[:service_name])
    cookbook 'docker_deploy'
    source 'wrapper_script.erb'
    mode '0755'
    variables({
      :service_name => params[:service_name],
      :actions => {
        'start' => "docker start #{params[:service_name]}",
        'stop' => "docker stop #{params[:service_name]}",
        'restart' => "docker restart #{params[:service_name]}",
        'attach' => "docker exec -it #{params[:service_name]} /bin/bash",
      }
    })
    action enable ? :create : :delete
  end
end
