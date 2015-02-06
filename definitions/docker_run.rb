define :docker_run do

  ## get project specific image (if available)
  docker_deploy_image "#{params[:project_image_name]}_pull" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action :try_pull_if_missing
  end

  ## start container
  docker_deploy_container "#{params[:container_name]}_start" do
    name params[:container_name]
    base_image params[:project_image_name]
    base_image_tag params[:project_image_tag]
    node_name params[:chef_node_name]
    port_bindings params[:port_bindings]
    binds params[:binds]
    env params[:env]
    container_create_options params[:container_create_options]
    encrypted_data_bag_secret params[:encrypted_data_bag_secret]
    validation_key params[:validation_key]
    keep_releases params[:keep_releases]
    action :create_and_rotate
    only_if { Docker::Image.exist?("#{params[:project_image_name]}:#{params[:project_image_tag]}") }
  end
end
