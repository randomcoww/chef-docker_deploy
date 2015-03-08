## hacked together from chef cookbook synchronizer to just do the cookbook download.

require 'chef/mixin/create_path'
include Chef::Mixin::CreatePath

class Chef
  class CookbookSynchronizer

    def download_container_cookbooks(base_path)

      @eager_segments = Chef::CookbookVersion::COOKBOOK_SEGMENTS.dup
      @eager_segments.freeze

      Chef::Log.info("Loading cookbooks [#{cookbooks.map {|ckbk| ckbk.name + '@' + ckbk.version}.join(', ')}]")
      Chef::Log.debug("Cookbooks detail: #{cookbooks.inspect}")

      queue = Chef::Util::ThreadedJobQueue.new

      files.each do |file|
        queue << lambda do |lock|

          raw_file = server_api.get_rest(file.manifest_record['url'], true)

          file_name = ::File.join(base_path, file.cookbook.name, file.manifest_record['path'])
          file_name = ::File.expand_path(file_name)

          create_path(::File.dirname(file_name))
          ::FileUtils.mv(raw_file, file_name)

          lock.synchronize {
            #mark_file_synced(file)
          }
        end
      end

      #@events.cookbook_sync_start(cookbook_count)
      queue.process(Chef::Config[:cookbook_sync_threads])
      # Update the full file paths in the manifest

    rescue Exception => e
      #@events.cookbook_sync_failed(cookbooks, e)
      raise
    else
      #@events.cookbook_sync_complete
      true
    end
  end
end
