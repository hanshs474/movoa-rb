# Official SDK for Movoa (https://movoa.ai), the AI video generator with sound.
#
#   require "movoa"
#   clip  = Movoa.generate_video("a paper lantern drifting over a night river")
#   moved = Movoa.generate_video("the camera slowly orbits the statue",
#                                image_url: "https://example.com/statue.jpg")
#
# Set MOVOA_API_KEY (create a key at https://movoa.ai/settings/apikeys).
# Runs cost credits on your Movoa account, at the prices on https://movoa.ai/pricing.
require "json"
require "net/http"
require "uri"
require_relative "movoa/version"

module Movoa
  BASE_URL = "https://movoa.ai".freeze
  KEYS_URL = "https://movoa.ai/settings/apikeys".freeze
  DEFAULT_MODEL = "minimax-h3".freeze
  MODELS = %w[minimax-h3 veo-3-1-fast seedance-2-5 seedance-2 seedance-2-fast seedance-2-mini].freeze

  # Base of every error this gem raises. #status is the HTTP status, #code the
  # envelope code, #reason the data.reason the service sent, if any.
  class Error < StandardError
    attr_reader :status, :code, :reason, :task_id
    def initialize(msg = nil, status: nil, code: nil, reason: nil, task_id: nil)
      super(msg)
      @status = status
      @code = code
      @reason = reason
      @task_id = task_id
    end
  end
  # No API key, or the key is invalid or deleted.
  class AuthError < Error; end
  # The account does not have enough credits for this run.
  class QuotaError < Error; end
  # The model or quality needs a plan, or the account has never bought credits.
  class PlanError < Error; end
  # Too many runs on this account are generating at once.
  class BusyError < Error; end
  # The content filter refused the prompt (code -2) or a cooldown is active (code -3); reword it.
  class RejectedError < Error; end
  # The run was accepted but ended as failed or canceled. #error_message says why.
  class GenerationError < Error
    attr_reader :error_message, :failure_kind
    def initialize(msg, task_id:, error_message: nil, failure_kind: nil)
      super(msg, task_id: task_id)
      @error_message = error_message
      @failure_kind = failure_kind
    end
  end
  # The wait ran out; the run may still finish. #task_id lets you check it later.
  class TimeoutError < Error; end

  # Map a refusal to the error that says what to do next. movoa.ai answers
  # almost every refusal as HTTP 200 with a non-zero code and a data.reason.
  def self.classify(status, body)
    body = {} unless body.is_a?(Hash)
    msg = body["message"].to_s
    msg = "request failed (HTTP #{status})" if msg.empty?
    code = body["code"].is_a?(Integer) ? body["code"] : nil
    reason = body["data"].is_a?(Hash) && body["data"]["reason"].is_a?(String) ? body["data"]["reason"] : nil
    klass =
      if status == 401 then AuthError
      elsif [-2, -3].include?(code) then RejectedError
      elsif reason == "insufficient_credits" then QuotaError
      elsif reason == "plan_required" then PlanError
      elsif reason == "concurrency" then BusyError
      elsif msg.downcase.include?("no auth") then AuthError
      else Error
      end
    msg = "#{msg} (create a key at #{KEYS_URL})" if klass == AuthError && !msg.include?(KEYS_URL)
    klass.new(msg, status: status, code: code, reason: reason)
  end

  # A client bound to one API key. transport: is a callable (url, body, key) -> [status, raw_body_string], for tests.
  class Client
    attr_accessor :poll_every, :timeout

    def initialize(api_key = nil, base_url: nil, poll_every: 10, timeout: 1800, transport: nil)
      @key = (api_key || ENV["MOVOA_API_KEY"]).to_s.strip
      base = base_url || ENV["MOVOA_BASE_URL"]
      @base = (base.nil? || base.strip.empty? ? BASE_URL : base.strip).chomp("/")
      @poll_every = poll_every
      @timeout = timeout
      @transport = transport || method(:http)
    end

    # Start a run and return its task id without waiting. image_url: makes it photo to video.
    # Other keyword arguments go into "options" as they are (duration:, resolution:, aspect_ratio:).
    def submit(prompt, model: DEFAULT_MODEL, image_url: nil, **options)
      raise ArgumentError, "prompt is required" if prompt.to_s.strip.empty?

      opts = { "sound" => true }
      options.each { |k, v| opts[k.to_s] = v unless v.nil? }
      opts["image_input"] = [image_url] if image_url
      body = {
        # The server routes by model; this only has to be non-empty.
        "provider" => "auto",
        "mediaType" => "video",
        "model" => model,
        "scene" => image_url ? "image-to-video" : "text-to-video",
        "prompt" => prompt,
        "options" => opts
      }
      data = call("/api/ai/generate", body)["data"]
      id = data.is_a?(Hash) ? data["id"] : nil
      raise Error, "movoa.ai accepted the run but returned no id" if id.nil? || id.to_s.empty?

      id.to_s
    end

    # Look up a run; returns the API's data hash ("id", "status", "videos", "errorMessage", "queued", "queueEta", ...).
    def status(task_id)
      data = call("/api/ai/query", { "taskId" => task_id })["data"]
      data.is_a?(Hash) ? data : {}
    end

    # Credits left on the account.
    def credits
      data = call("/api/user/get-user-credits", nil)["data"]
      data.is_a?(Hash) ? data["remainingCredits"].to_i : 0
    end

    # Submit, wait, and return the URL of the finished clip.
    def generate_video(prompt, model: DEFAULT_MODEL, image_url: nil, **options)
      wait(submit(prompt, model: model, image_url: image_url, **options))
    end

    # Wait for a submitted run and return its video URL.
    def wait(task_id)
      deadline = Time.now + @timeout
      loop do
        d = status(task_id)
        case d["status"]
        when "success"
          videos = d["videos"]
          raise GenerationError.new("run #{task_id} finished with no video", task_id: task_id) unless videos.is_a?(Array) && !videos.empty?

          return videos.first.to_s
        when "failed", "canceled"
          em = d["errorMessage"]
          raise GenerationError.new("run #{task_id} #{d['status']}#{em ? ": #{em}" : ''}",
                                    task_id: task_id, error_message: em, failure_kind: d["failureKind"])
        end
        if Time.now + @poll_every > deadline
          raise TimeoutError.new("run #{task_id} is still generating; check it later with status", task_id: task_id)
        end

        sleep @poll_every
      end
    end

    private

    def call(path, body)
      raise AuthError, "set MOVOA_API_KEY or pass api_key; create a key at #{KEYS_URL}" if @key.empty?

      status, raw = @transport.call("#{@base}#{path}", body, @key)
      parsed = begin
        raw.to_s.strip.empty? ? {} : JSON.parse(raw.to_s)
      rescue JSON::ParserError
        nil
      end
      raise Movoa.classify(401, {}) if status == 401 && !parsed.is_a?(Hash)
      raise Error.new("movoa.ai returned a non-JSON response (HTTP #{status})", status: status) unless parsed.is_a?(Hash)
      return parsed if status < 400 && parsed["code"] == 0

      raise Movoa.classify(status, parsed)
    end

    def http(url, body, key)
      uri = URI(url)
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{key}"
      req["User-Agent"] = "movoa-ruby/#{VERSION}"
      req.body = JSON.generate(body) unless body.nil?
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 60) { |h| h.request(req) }
      [res.code.to_i, res.body.to_s]
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error, "could not reach movoa.ai: #{e.message}"
    end
  end

  # Generate one clip with sound (minimax-h3 by default) and return its URL.
  def self.generate_video(prompt, model: DEFAULT_MODEL, image_url: nil, api_key: nil, **options)
    Client.new(api_key).generate_video(prompt, model: model, image_url: image_url, **options)
  end

  # Start a run and return its task id.
  def self.submit(prompt, model: DEFAULT_MODEL, image_url: nil, api_key: nil, **options)
    Client.new(api_key).submit(prompt, model: model, image_url: image_url, **options)
  end

  # Look up a run.
  def self.status(task_id, api_key: nil)
    Client.new(api_key).status(task_id)
  end

  # Credits left on the account.
  def self.credits(api_key: nil)
    Client.new(api_key).credits
  end
end
