define :docker_push do

  class Chef::ResourceDefinitionList
    include DockerHelper
  end

  enable = params[:enable_service]
  base_image_exists = DockerWrapper::Image.exists?("#{params[:initial_base_image_name]}:#{params[:initial_base_image_tag]}")
  image_exists = DockerWrapper::Image.exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}")

  ## auth

  ## base image
  docker_deploy_image "#{params[:project_base_image_name]}_push" do
    name params[:project_base_image_name]
    tag params[:project_base_image_tag]
    action :push
    only_if { enable and base_image_exists }
  end
  
  ## revision image
  docker_deploy_image "#{params[:project_image_name]}_push" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action :push
    only_if { enable and image_exists }
  end
end
