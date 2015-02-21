class Chef::Resource
  include DockerWrapper
  end

## remove any images not referenced by a container or another image
ruby_block "remove_unused_images" do
  block do
    puts "Removing unused images"
    list_dangling_images.each do |i_id|
      begin
        docker_rmi(i_id)
        puts "Image deleted: #{i_id}"
      rescue
        puts "Image in use: #{i_id}"
      end
    end
  end
end
