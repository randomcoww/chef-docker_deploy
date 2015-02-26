define :docker_push do

  class Chef::Resource
    include DockerHelper

    def image_exists
      DockerWrapper::Image.exists?("#{params[:image]}:#{params[:tag]}")
    end
  end

  enable = params[:enable_service]

  ## auth

  ## base image
  docker_deploy_image "#{params[:image]}_push" do
    name params[:image]
    tag params[:tag]
    action :push
    only_if { enable and image_exists }
  end
end
