# movoa

Unlimited AI video generator with sound: on paid plans the tenth take of a shot costs what the first did, and your first clip is free to make right now. This is the official Ruby SDK for [Movoa](https://movoa.ai/?utm_source=rubygems&utm_medium=package): one API key turns a prompt into [text to video](https://movoa.ai/video/text-to-video), or a still into [photo to video](https://movoa.ai/video/photo-to-video), and every clip comes back as [AI video with audio](https://movoa.ai/video/ai-video-with-audio).

```ruby
require "movoa"

clip = Movoa.generate_video("a paper lantern drifting over a night river, slow dolly")
puts clip # URL of the finished MP4, sound included
```

`generate_video` submits the run, waits for it and returns the URL of the finished file.

## Install

```bash
gem install movoa
```

Standard library only (`net/http`, `json`), Ruby 2.6+.

## API key

Sign in on [movoa.ai](https://movoa.ai/?utm_source=rubygems&utm_medium=package), create a key at [movoa.ai/settings/apikeys](https://movoa.ai/settings/apikeys), then pass it as `api_key:` or export it:

```bash
export MOVOA_API_KEY=sk-...
```

Runs cost credits on your Movoa account, at the prices on [movoa.ai/pricing](https://movoa.ai/pricing).

```ruby
Movoa.credits # remaining credits on the account
```

## Text to video and photo to video

```ruby
# text to video, vertical, 10 seconds
Movoa.generate_video("a fox trotting through fresh snow at dawn", duration: 10, aspect_ratio: "9:16")

# photo to video: the photo becomes the first frame
Movoa.generate_video("the camera slowly orbits the statue", image_url: "https://example.com/statue.jpg")

# another model
Movoa.generate_video("a street drummer in the rain", model: "seedance-2-5", resolution: "720p")
```

| model | options |
|---|---|
| `minimax-h3` (default) | `duration` 4 / 5 / 6 / 8 / 10 / 15 · `resolution` 480p / 768p · `aspect_ratio` 16:9 / 9:16 / 1:1 |
| `veo-3-1-fast` | `duration` 8 · `resolution` 720p · `aspect_ratio` 16:9 / 9:16 (photo to video: 16:9) |
| `seedance-2-5` | `duration` 5 / 10 / 15 / 20 / 25 / 30 · `resolution` 480p / 720p · `aspect_ratio` 16:9 / 9:16 / 1:1 |
| `seedance-2`, `seedance-2-fast`, `seedance-2-mini` | `duration` 4 / 6 / 8 / 10 · `resolution` 480p / 720p · `aspect_ratio` |

Any other keyword argument is sent in `options` as it is. Every run asks for sound. On the site: [Seedance 2.5](https://movoa.ai/video/seedance-2-5) and [Veo 3](https://movoa.ai/video/google-veo-3).

## Submit now, collect later

```ruby
c = Movoa::Client.new                  # reads MOVOA_API_KEY
id = c.submit("a lighthouse in a storm", duration: 6)
c.status(id)["status"]                 # pending | processing | success | failed | canceled
url = c.wait(id)                       # polls every 10 seconds, 30 minutes by default
```

While a run waits in line, `status` returns `"queued" => true` and `"queueEta"` in seconds.

## Errors worth rescuing

All inherit from `Movoa::Error`:

- `Movoa::AuthError`: no key, or the key is wrong or deleted; create one at [movoa.ai/settings/apikeys](https://movoa.ai/settings/apikeys)
- `Movoa::QuotaError`: the account does not have enough credits for this run
- `Movoa::PlanError`: that model or quality needs a plan on the account
- `Movoa::BusyError`: too many runs on this account are generating at once
- `Movoa::RejectedError`: the content filter refused the prompt, or a cooldown is active; reword it
- `Movoa::GenerationError`: the run was accepted but failed or was canceled; `#error_message` says why
- `Movoa::TimeoutError`: the wait ran out; `#task_id` lets you check the run later

Any other refusal raises `Movoa::Error` with the server's message.

MIT licensed. Made by [Movoa](https://movoa.ai/?utm_source=rubygems&utm_medium=package).
