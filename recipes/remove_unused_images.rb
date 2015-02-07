require 'docker'

# search and remove unused images after creating container. this will remove any images (regardless of proejct) not a parent of a container or another image
# intended to clean out things like failed builds. there is no recursion so it may take a few runs to clean out images with many levels of child images
ruby_block 'remove_unused_images' do
  block do
    ::Docker::Image.all.each do |image|
      image.remove_non_active
    end
  end
end
