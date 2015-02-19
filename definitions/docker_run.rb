define :docker_run do

  class Chef::Resource
    include DockerWrapper
  end

  enable = params[:enable_service]

  ## get project specific image (if available)
  docker_deploy_image "#{params[:project_image_name]}_pull" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action :try_pull_if_missing
    only_if { enable }
  end

  ## start container
  docker_deploy_container "#{params[:container_name]}_start" do
    name params[:container_name]
    base_image params[:project_image_name]
    base_image_tag params[:project_image_tag]
    node_name "#{node.hostname}-#{params[:container_name]}"
    container_create_options params[:container_create_options]
    encrypted_data_bag_secret params[:encrypted_data_bag_secret]
    validation_key params[:validation_key]
    chef_admin_user params[:chef_admin_user]
    chef_admin_key params[:chef_admin_key]
    keep_releases params[:keep_releases]
    action enable ? :create_and_rotate : :remove
    only_if { !enable or get_exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}") }
  end
end
