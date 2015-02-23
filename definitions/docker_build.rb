define :docker_build do

  #class Chef::Resource
  #  include DockerWrapper
  #end

  enable = params[:enable_service]

  ## get the initial base image
  docker_deploy_image "#{params[:initial_base_image_name]}_pull" do
    name params[:initial_base_image_name]
    tag params[:initial_base_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
  end
  
  ## get project specific base image (if available)
  docker_deploy_image "#{params[:project_base_image_name]}_pull" do
    name params[:project_base_image_name]
    tag params[:project_base_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
    ignore_failure true
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
    chef_admin_user params[:chef_admin_user]
    chef_admin_key params[:chef_admin_key]
    docker_build_commands params[:docker_build_commands]
    action :build_if_missing
    #only_if { enable and DockerWrapper::Image.get("#{params[:initial_base_image_name]}:#{params[:initial_base_image_tag]}").exists? }
  end

  ## push
#  docker_deploy_image "#{params[:project_base_image_name]}_push" do
#    name params[:project_base_image_name]
#    tag params[:project_base_image_tag]
#    action :push
#    only_if { enable and get_exists?("#{params[:project_base_image_name]}:#{params[:project_base_image_tag]}") }
#  end
  
  ## get project specific image (if available)
  docker_deploy_image "#{params[:project_image_name]}_pull" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action enable ? :pull_if_missing : :remove_if_unused
    ignore_failure true
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
    chef_admin_user params[:chef_admin_user]
    chef_admin_key params[:chef_admin_key]
    action :build_if_missing
    only_if { enable and DockerWrapper::Image.get("#{params[:project_base_image_name]}:#{params[:project_base_image_tag]}").exists? }
  end

  ## push
#  docker_deploy_image "#{params[:project_image_name]}_push" do
#    name params[:project_image_name]
#    tag params[:project_image_tag]
#    action :push
#    only_if { enable and get_exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}") }
#  end
end
