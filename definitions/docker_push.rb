define :docker_push do

  class Chef::Resource
    include DockerHelper

    def project_base_image_exists
      DockerWrapper::Image.exists?("#{params[:project_base_image_name]}:#{params[:project_base_image_tag]}")
    end

    def project_image_exists
      DockerWrapper::Image.exists?("#{params[:project_image_name]}:#{params[:project_image_tag]}")
    end
  end

  enable = params[:enable_service]

  ## auth

  ## base image
  docker_deploy_image "#{params[:project_base_image_name]}_push" do
    name params[:project_base_image_name]
    tag params[:project_base_image_tag]
    action :push
    only_if { enable and project_base_image_exists }
  end
  
  ## revision image
  docker_deploy_image "#{params[:project_image_name]}_push" do
    name params[:project_image_name]
    tag params[:project_image_tag]
    action :push
    only_if { enable and project_image_exists }
  end
end
