require_relative "../lib/studio/d64"
require_relative "../lib/studio/client_import"
require "fileutils"

ActiveRecord::Base.logger = nil
ActiveJob::Base.logger = Logger.new(nil)

address = ENV.fetch("STORES_ADDRESS")
name = ENV.fetch("STORES_NAME", "My Studio")
id = ENV.fetch("STORES_ID", "mystudio")
logo = ENV.fetch("STORES_LOGO", "")
app_url = "http://#{address}:#{ENV.fetch('APP_PORT', '8080')}"
shelf_http_port = ENV.fetch("SHELF_HTTP_PORT", "8090")
shelf_ftp_port = ENV.fetch("SHELF_FTP_PORT", "2121")
public_dir = Rails.root.join("public/stores")

step = ->(text) { puts "  #{text}" }

import = Studio::ClientImport.new(source: ENV.fetch("STORES_SOURCE", "https://teletypegames.org"),
                                  local: "http://localhost:3000", secret: ENV.fetch("UPDATE_SECRET", "example-update-secret"))
clients = {}
%w[we-c64 we-dos we-batocera we-retroarch].each do |client|
  clients[client] = import.call(client)
  step.call("#{client} #{clients[client]} is in the catalog, released")
end

prg_path = Dir[File.join(WarpEngine.config.file_container_path.to_s, "we-c64", clients["we-c64"], "*.prg")].first or raise "no WE64 .prg in the release"
disk = Studio::D64.new(name[0, 16], "01")
  .add("we64", File.binread(prg_path))
  .add("we64.cfg", "HOST=#{address}\nPORT=#{shelf_http_port}\nPATH=/C64\n", type: :seq)
FileUtils.mkdir_p(public_dir.join("c64"))
File.binwrite(public_dir.join("c64/#{id}.d64"), disk.to_s)
step.call("c64/#{id}.d64: WE64 and its WE64.CFG (#{clients['we-c64']})")

dos_zip = Dir[File.join(WarpEngine.config.file_container_path.to_s, "we-dos", clients["we-dos"], "we-dos-#{clients['we-dos']}.zip")].first or raise "no WEDOS zip in the release"
FileUtils.mkdir_p(public_dir.join("dos"))
target = public_dir.join("dos/we-dos.zip")
FileUtils.cp(dos_zip, target)
inside = IO.popen([ "unzip", "-Z1", target.to_s ], &:read).lines.map(&:chomp).find { |entry| File.basename(entry).casecmp?("WEDOS.CFG") } || "WEDOS/WEDOS.CFG"
Dir.mktmpdir do |dir|
  FileUtils.mkdir_p(File.join(dir, File.dirname(inside)))
  File.binwrite(File.join(dir, inside), "SERVER=#{address}\r\nPORT=#{shelf_ftp_port}\r\nPATH=/APPS\r\nDEST=C:\\APPS\r\n")
  system("zip", "-q", target.to_s, inside, chdir: dir, exception: true)
end
step.call("dos/we-dos.zip: WEDOS and its WEDOS.CFG (#{clients['we-dos']})")

logo_urls =
  if logo.match?(%r{\Ahttps?://})
    [ logo ]
  elsif logo.present? && File.file?(logo)
    FileUtils.mkdir_p(public_dir)
    FileUtils.cp(logo, public_dir.join("logo#{File.extname(logo).downcase}"))
    [ "#{app_url}/stores/logo#{File.extname(logo).downcase}" ]
  else
    []
  end
%w[batocera retroarch].each do |client|
  WarpEngine::StoreClient.for(client).update!(name: name, store_key: id, logo_urls: logo_urls)
  step.call("#{client}: served by the catalog as #{name} (#{id})")
end

puts
puts "#{name}, for every screen (the catalog at #{app_url}):"
puts
puts "  Batocera     curl -fsSL #{app_url}/api/stores/batocera/install.sh | sh"
puts "  RetroArch    curl -fsSL #{app_url}/api/stores/retroarch/install.sh | sh"
puts "  C64          #{app_url}/stores/c64/#{id}.d64  (on the Ultimate's SD card or in VICE: LOAD \"WE64\",8 and RUN)"
puts "  DOS          #{app_url}/stores/dos/we-dos.zip  (unpack, run WEDOS.EXE)"
puts "  Desktop      the WarpEngine Desktop: give it #{app_url} on its first run"
