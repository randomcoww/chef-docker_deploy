class Chef::Provider
  include DockerDeploy
  include DockerDeploy::Error
end

require 'docker'

ruby_block 'remove_unused_images' do
  block do
    Chef::Log.info('Cleaning up unused images')

    Docker::Image.all do |image|
      image.remove_non_active
    end
  end
end
