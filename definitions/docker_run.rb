define :docker_run do

  class Chef::Resource
    include DockerHelper

    def project_image_exists
      DockerWrapper::Image.exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}")
    end
  end

  enable = params[:enable_service]

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
    name params[:service_name]
    base_image params[:project_image_name]
    base_image_tag params[:project_image_tag]
    node_name "#{node.hostname}-#{params[:service_name]}"
    container_create_options params[:container_create_options]
    encrypted_data_bag_secret params[:encrypted_data_bag_secret]
    validation_key params[:validation_key]
    chef_admin_user params[:chef_admin_user]
    chef_admin_key params[:chef_admin_key]
    keep_releases params[:keep_releases]
    action enable ? :create : :remove
    not_if { enable and !project_image_exists }
  end
end
