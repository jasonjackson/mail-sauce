#!/usr/bin/env ruby

require 'resque'
require 'resque/job_with_status'

# This is a simple Resque job.
class Priority < Resque::JobWithStatus
  require File.dirname(__FILE__) + '/../../../services/emailer/lib/content'

  @queue = :priority

  def self.perform(payload)
    payload_array = ::JSON.parse payload
    content_hash = payload_array[0]
    envelope = payload_array[1]

    Content.setup_fs

    tmp_files = "#{AGENT_CONTENT_PATH}/#{content_hash['listname']}"

    # Is the local file there and newer than 12 hours old?  If not pull from redis.
    unless File.exist?("#{tmp_files}.html") && File.new("#{tmp_files}.html").mtime > Time.now - 43200
      Content.refresh_content(tmp_files,content_hash)
    end

    Content.process_envelope(envelope,content_hash,tmp_files)
  end

end
