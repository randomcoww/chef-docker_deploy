class Chef::Resource
  include DockerWrapper
  end

## remove any images not referenced by a container or another image
ruby_block "remove_unused_images" do
  block do
    list_all_images.each do |i_id|
      begin
        docker_rmi(i_id)
      rescue
        puts "Image #{i_id} in use"
      end
    end
  end
end
