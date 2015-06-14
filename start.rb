require 'rubygems'
require 'bundler'
Bundler.setup
require 'soundcloud'
require 'slack-rtmapi'
require 'http'
require 'json'

USER_TOKEN = ENV["SLACK_USER_TOKEN"]

AUTH = {client_id: ENV['SOUNDCLOUD_AUTH_CLIENT_ID'],
        client_secret: ENV['SOUNDCLOUD_AUTH_CLIENT_SECRET']}

@users = ["chunkybeats25", "jhsu", "nlaf"]

@client = SoundCloud.new({
  client_id: AUTH[:client_id],
  client_secret: AUTH[:client_secret],
  username: 'jhsu',
  password: ENV['SOUNDCLOUD_PASSWORD']
})
INCOMING_URL = ENV["SLACK_WEBHOOK_INCOMING"]
RTM_URL = SlackRTM.get_url(token: USER_TOKEN)

# Get the liked track of a user.
# If a user didn't like the track, then return nil.
def get_liked(username, track_id)
  @client.get("/users/#{username}/favorites/#{track_id}")
  rescue SoundCloud::ResponseError
end

def resolve_url(url)
  @client.get("/resolve", url: url, client_id: AUTH[:client_id])
  rescue SoundCloud::ResponseError
end

# returns an array of usernames that liked the track
# ie:
#     who_likes("...")
#     #=> ["jhsu"]
def who_likes(url)
  track = resolve_url(url)
  if track && track.kind == "track"
    @users.map {|username|
      if get_liked(username, track.id)
        username
      end
    }.compact
  else # TODO: handle if track isn't found
    []
  end
end

@rtmclient = SlackRTM::Client.new(websocket_url: RTM_URL)
@rtmclient.on(:message) do |data|
  if data["type"] == "message" && !data["hidden"]
    urls = data["text"].scan(/https:\/\/soundcloud\.com\/[^\/\s]+\/[^\/\s>]+/i)
    if urls.any?
      channel_response = HTTP.get("https://slack.com/api/channels.info", params: {token: USER_TOKEN, channel: data['channel']})
      channel_info = JSON.parse(channel_response.body)['channel']
      channel_name = channel_info['name']
      urls.each do |url|
        usernames = who_likes(url)
        if usernames.any?
          payload = {
            username: "soundlikes",
            channel: "##{channel_name}",
            text: "Liked by users: #{usernames.join(", ")}"
          }
          HTTP.post(INCOMING_URL, json: payload)
        end
      end
    end
  end
end
@rtmclient.main_loop

loop do
  sleep 1
end
