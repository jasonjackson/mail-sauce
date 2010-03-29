class Content
  require 'rubygems'
  require 'net/smtp'
  require 'fileutils'
  require 'json'
  require 'syslog'
  require File.dirname(__FILE__) + '/../../../lib/tenjin'
  require File.dirname(__FILE__) + '/../../../lib/tmail'
  require File.dirname(__FILE__) + '/../../../services/emailer/config/servers.rb'
  require File.dirname(__FILE__) + '/../../../services/emailer/config/content.rb'

  def self.to_syslog(tag,string)
      Syslog.open(tag)
      Syslog.info(string)
      Syslog.close
  end

  def self.write_io(path,io)
    ::File.open(path, 'w') { |f| f.write(io) }
  end

  def self.generate_hash(email)
    seed = SEED
    hash = ::Digest::MD5.hexdigest("#{email.downcase}#{seed}")
    return hash
  end

    ::FileUtils.rm_r Dir.glob("#{tmp_files}.*"), :force => true
    self.write_io("#{tmp_files}.html", content_store["#{content_hash['listname']}-html"])
    self.write_io("#{tmp_files}.html.cache", content_store["#{content_hash['listname']}-chtml"])
    self.write_io("#{tmp_files}.sub", content_store["#{content_hash['listname']}-sub"])
    self.write_io("#{tmp_files}.sub.cache", content_store["#{content_hash['listname']}-csub"])
    self.write_io("#{tmp_files}.txt", content_store["#{content_hash['listname']}-txt"])
    self.write_io("#{tmp_files}.txt.cache", content_store["#{content_hash['listname']}-ctxt"])
  end

  def self.generate_email(html_output,txt_output,sub_output,content_id,member_email)
    email = ::TMail::Mail.new
    email.to = member_email
    email.from = "Monster.com <updates@monster.com>"
    email.subject = sub_output
    email.date = ::Time.now
    email.mime_version = '1.0'
    email['Return-Path'] = 'updates@monster.com'
    if txt_output  
        part = TMail::Mail.new
        part.body = txt_output
        part.set_content_type 'text', 'plain', {'charset' => 'utf8'}
        part.transfer_encoding = '8bit'
        part.set_content_disposition "inline"
        email.parts << part
    end
    if html_output
#      self.add_part(email,html_output)
        part = TMail::Mail.new
        part.body = html_output
        part.set_content_type 'text', 'html', {'charset' => 'utf8'}
        part.transfer_encoding = '8bit'
        part.set_content_disposition "inline"
        email.parts << part
    end
    email.set_content_type("multipart/alternative", nil, {"charset" => "utf8", "boundary" => ::TMail.new_boundary})
    # X-Headers
    email['X-Campaignid'] = content_id
    msg = email.to_s
    return msg
  end

  def self.process_envelope(envelope,content_hash,tmp_files)
    content_id  = "#{DOMAIN.gsub('.','_')}-#{content_hash['listname']}-#{content_hash['timestamp']}"
    engine = ::Tenjin::Engine.new

    envelope.each do |member|
      context = { :email => member['email'],
                  :fname => member['fname'],
                  :lname => member['lname'],
                  :hash => generate_hash(member['email'])
      }

      # Render the content via the tenjin engine
      html_output = engine.render("#{tmp_files}.html", context)
      txt_output = engine.render("#{tmp_files}.txt", context)
      sub_output = engine.render("#{tmp_files}.sub", context)

      begin
        smtp = Net::SMTP.start(SMTP_SERVER, SMTP_PORT)
        smtp.send_message self.generate_email(html_output,txt_output,sub_output,content_id,member['email']), "Monster.com <updates\@monster.com>", member['email']
        smtp.finish
      rescue Exception => e
        self.to_syslog("Emailer Exception: General exception raised.  Most likely the connection was denied to the SMTP server.  Retrying..",e)
        sleep(2)
        retry
      rescue IOError => e
        self.to_syslog("Emailer Exception: IO Error to SMTP server",e)
        sleep(2)
        retry
      rescue Timeout::Error => e
        self.to_syslog("Emailer Exception: Connection timeout to the SMTP server, reconnecting.",e)
        sleep(2)
        retry
      rescue Net::SMTPServerBusy => e
        self.to_syslog("Emailer Exception: SMTP server is busy, will sleep 2 and try resuming.",e)
        sleep(2)
        retry
      rescue Net::SMTPUnknownError => e
        self.to_syslog("Emailer Exception: SMTP unknown error.  Probably bad, try to resume and sending alarm.",e)
        sleep(2)
        retry
      rescue Net::SMTPSyntaxError => e
        self.to_syslog("Emailer Exception: SMTP syntax error.  Probably bad, try to resume and sending alarm.",e)
        sleep(2)
        retry
      end
    end
    puts "Envelope sent for #{content_hash['listname']}"
  end

  def self.setup_fs
    # Create the content directory on the local box if it doesn't exist
    unless ::File.exist?(AGENT_CONTENT_PATH)
      ::FileUtils.mkdir_p AGENT_CONTENT_PATH
    end
  end

end
