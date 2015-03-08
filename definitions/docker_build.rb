define :docker_build do

  class Chef::Resource
    include DockerHelper
    
    def initial_image_exists
       DockerWrapper::Image.exists?("#{params[:initial_base_image_name]}:#{params[:initial_base_image_tag]}")
    end

    def project_base_image_exists
       DockerWrapper::Image.exists?("#{params[:project_base_image_name]}:#{params[:project_base_image_tag]}")
    end

    def project_image_exists
        DockerWrapper::Image.exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}")
    end
  end

  enable = params[:enable_service]

  ## get the initial base image
  docker_deploy_image "#{params[:initial_base_image_name]}_pull" do
    name params[:initial_base_image_name]
    tag params[:initial_base_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
    not_if { enable and initial_image_exists }
  end
  
  ## get project specific base image (if available)
  docker_deploy_image "#{params[:project_base_image_name]}_pull" do
    name params[:project_base_image_name]
    tag params[:project_base_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
    ignore_failure true
    not_if { enable and project_base_image_exists }
  end

  ## otherwise build service specific base image
  docker_deploy_image "#{params[:project_base_image_name]}_build" do
    name params[:project_base_image_name]
    tag params[:project_base_image_tag]
    base_image params[:initial_base_image_name]
    base_image_tag params[:initial_base_image_tag]
    chef_environment params[:project_environment]
    first_boot params[:first_boot]
    encrypted_data_bag_secret params[:encrypted_data_bag_secret]
    validation_key params[:validation_key]
    dockerfile_commands params[:dockerfile_commands]
    action :build_if_missing
    only_if { enable and initial_image_exists }
  end

  ## get project specific image (if available)
  docker_deploy_image "#{params[:project_image_name]}_pull" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
    ignore_failure true
    not_if { enable and project_image_exists }
  end

  ## otherwise build service specific image
  docker_deploy_image "#{params[:project_image_name]}_build" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    base_image params[:project_base_image_name]
    base_image_tag params[:project_base_image_tag]
    chef_environment params[:project_environment]
    first_boot params[:first_boot]
    encrypted_data_bag_secret params[:encrypted_data_bag_secret]
    validation_key params[:validation_key]
    enable_local_mode params[:enable_local_mode]
    local_data_bags params[:local_data_bags]
    action :build_if_missing
    only_if { enable and project_base_image_exists }
  end
end
