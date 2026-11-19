require "json"
require "net/http"
require "tmpdir"

module Studio
  # Copies the newest stable release of a software from another WarpEngine
  # catalog into this one, through this catalog's own build endpoints, and
  # marks the software released. A release already here is left alone.
  class ClientImport
    def initialize(source:, local:, secret:)
      @source = source.chomp("/")
      @local = local.chomp("/")
      @secret = secret
    end

    def call(name)
      item = find(name) or raise ArgumentError, "#{name} is not in #{@source}"
      release = item["latestRelease"] or raise ArgumentError, "#{name} has no release in #{@source}"
      version = release.fetch("version")
      unless here?(name, version)
        Dir.mktmpdir do |dir|
          files(name, version, release).each { |path| upload(name, version, download(path, dir)) }
        end
        publish(name, version, item.dig("software", "platform"))
      end
      ActiveRecord::Base.uncached { WarpEngine::Software.kept.find_by!(name: name).update!(status: "released") }
      version
    end

    private

    def find(name)
      body = get("#{@source}/api/software?api=2&perPage=200")
      JSON.parse(body).fetch("softwares").find { |item| item.dig("software", "name") == name }
    end

    def here?(name, version)
      ActiveRecord::Base.uncached { WarpEngine::Software.kept.find_by(name: name)&.releases&.exists?(version: version) || false }
    end

    def files(name, version, release)
      assets = release.fetch("assets").map { |asset| asset["path"] }.select { |path| File.extname(path).present? }
      assets + [ "/file/#{name}/#{version}/#{name}-#{version}.metadata.json" ]
    end

    def download(path, dir)
      File.join(dir, File.basename(path)).tap { |file| File.binwrite(file, get("#{@source}#{path}")) }
    end

    def upload(name, version, file)
      uri = URI("#{@local}/build/upload?#{URI.encode_www_form(name: name, version: version)}")
      request = Net::HTTP::Post.new(uri, "X-Update-Secret" => @secret)
      File.open(file, "rb") do |io|
        request.set_form([ [ "file", io, { filename: File.basename(file) } ] ], "multipart/form-data")
        check!(Net::HTTP.start(uri.host, uri.port, read_timeout: 600) { |http| http.request(request) }, "upload #{File.basename(file)}")
      end
    end

    def publish(name, version, platform)
      uri = URI("#{@local}/build/publish?#{URI.encode_www_form(platform: platform, name: name, version: version)}")
      request = Net::HTTP::Post.new(uri, "X-Update-Secret" => @secret)
      check!(Net::HTTP.start(uri.host, uri.port, read_timeout: 600) { |http| http.request(request) }, "publish #{name} #{version}")
    end

    def get(url, limit = 5)
      response = Net::HTTP.get_response(URI(url))
      return get(response["location"], limit - 1) if response.is_a?(Net::HTTPRedirection) && limit.positive?

      check!(response, "GET #{url}").body
    end

    def check!(response, what)
      return response if response.is_a?(Net::HTTPSuccess)

      raise "#{what}: #{response.code} #{response.body.to_s[0, 200]}"
    end
  end
end
