require "json"
require "minitest/autorun"
require_relative "../lib/movoa"

class MovoaTest < Minitest::Test
  OK_SUBMIT = [200, JSON.generate("code" => 0, "message" => "ok", "data" => { "id" => "t1", "status" => "pending" })].freeze

  # Replies in the real response shapes of movoa.ai: submit, then the polls in order (the last one repeats).
  def fake(calls, polls, submit_reply = OK_SUBMIT)
    n = 0
    lambda do |url, body, key|
      calls << [url, body, key]
      if url.end_with?("/api/ai/generate")
        submit_reply
      elsif url.end_with?("/api/ai/query")
        d = polls[[n, polls.size - 1].min]
        n += 1
        [200, JSON.generate("code" => 0, "message" => "ok", "data" => d)]
      else
        [200, JSON.generate("code" => 0, "message" => "ok", "data" => { "remainingCredits" => 42 })]
      end
    end
  end

  def client(calls, polls, submit_reply = OK_SUBMIT)
    Movoa::Client.new("sk-test", base_url: "https://t", poll_every: 0, transport: fake(calls, polls, submit_reply))
  end

  def test_text_to_video_success
    calls = []
    c = client(calls, [
      { "id" => "t1", "status" => "pending", "queued" => true, "queueEta" => 30 },
      { "id" => "t1", "status" => "processing" },
      { "id" => "t1", "status" => "success", "videos" => ["https://cdn/v.mp4"] }
    ])
    assert_equal "https://cdn/v.mp4", c.generate_video("a boat", duration: 6)
    assert_equal "https://t/api/ai/generate", calls[0][0]
    assert_equal "sk-test", calls[0][2]
    assert_equal({ "provider" => "auto", "mediaType" => "video", "model" => "minimax-h3", "scene" => "text-to-video",
                   "prompt" => "a boat", "options" => { "sound" => true, "duration" => 6 } }, calls[0][1])
    assert_equal({ "taskId" => "t1" }, calls[1][1])
    assert_equal 4, calls.size
    assert_equal 42, c.credits
  end

  def test_photo_to_video_body
    calls = []
    client(calls, []).submit("orbit", model: "seedance-2-5", image_url: "https://x/y.jpg", aspect_ratio: "9:16")
    assert_equal "image-to-video", calls[0][1]["scene"]
    assert_equal "seedance-2-5", calls[0][1]["model"]
    assert_equal({ "sound" => true, "aspect_ratio" => "9:16", "image_input" => ["https://x/y.jpg"] }, calls[0][1]["options"])
  end

  def test_error_mapping
    j = ->(h) { JSON.generate(h) }
    {
      [401, j.call("code" => -1, "message" => "Invalid API key. Create one at https://movoa.ai/settings/apikeys", "data" => { "reason" => "invalid_api_key" })] => Movoa::AuthError,
      [401, "<html>unauthorized</html>"] => Movoa::AuthError,
      [200, j.call("code" => -1, "message" => "insufficient credits", "data" => { "reason" => "insufficient_credits" })] => Movoa::QuotaError,
      [200, j.call("code" => -1, "message" => "This model or quality needs a plan.", "data" => { "reason" => "plan_required" })] => Movoa::PlanError,
      [200, j.call("code" => -1, "message" => "busy", "data" => { "reason" => "concurrency" })] => Movoa::BusyError,
      [200, j.call("code" => -2, "message" => "blocked")] => Movoa::RejectedError,
      [200, j.call("code" => -3, "message" => "cooldown")] => Movoa::RejectedError,
      [200, j.call("code" => -1, "message" => "no auth, please sign in")] => Movoa::AuthError,
      [200, j.call("code" => -1, "message" => "generation failed, please try again")] => Movoa::Error,
      [502, "Bad gateway"] => Movoa::Error
    }.each do |reply, klass|
      e = assert_raises(Movoa::Error) { client([], [], reply).submit("x") }
      assert_instance_of klass, e, reply.inspect
    end
  end

  def test_failed_and_canceled
    c = client([], [{ "id" => "t1", "status" => "failed", "errorMessage" => "provider down", "failureKind" => "upstream" }])
    e = assert_raises(Movoa::GenerationError) { c.generate_video("x") }
    assert_equal "provider down", e.error_message
    assert_equal "upstream", e.failure_kind
    assert_equal "t1", e.task_id
    assert_raises(Movoa::GenerationError) { client([], [{ "id" => "t1", "status" => "canceled" }]).wait("t1") }
  end

  def test_timeout_carries_task_id
    c = client([], [{ "id" => "t1", "status" => "processing", "queued" => true, "queueEta" => 60 }])
    c.timeout = 0.001
    c.poll_every = 0.01
    e = assert_raises(Movoa::TimeoutError) { c.wait("t1") }
    assert_equal "t1", e.task_id
  end

  def test_status_and_no_auth_credits
    st = client([], [{ "id" => "t1", "status" => "success", "videos" => ["https://cdn/v.mp4"] }]).status("t1")
    assert_equal "https://cdn/v.mp4", st["videos"][0]
    bad = Movoa::Client.new("sk", transport: ->(*) { [200, JSON.generate("code" => -1, "message" => "no auth, please sign in")] })
    assert_raises(Movoa::AuthError) { bad.credits }
  end

  def test_missing_key
    old = ENV.delete("MOVOA_API_KEY")
    assert_raises(Movoa::AuthError) { Movoa::Client.new(transport: ->(*) { flunk "no request without a key" }).credits }
  ensure
    ENV["MOVOA_API_KEY"] = old if old
  end

  # Live (after key auth is live on movoa.ai): MOVOA_LIVE=1 MOVOA_API_KEY=... ruby -Ilib test/test_movoa.rb
  def test_live_smoke
    skip "set MOVOA_LIVE=1" unless ENV["MOVOA_LIVE"]
    assert_operator Movoa.credits, :>=, 0
    assert_raises(Movoa::AuthError) { Movoa::Client.new("sk-wrong-key-for-test").submit("test") }
  end
end
