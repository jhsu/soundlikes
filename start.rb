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

# channel id => name cache
@channels = {}
@group_url = "https://soundcloud.com/groups/coolpeeps-music"
@group_id = nil

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
def who_likes(track)
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

def contribute_to_group(client, group_id, track)
  client.post("/groups/#{group_id}/contributions", {track: track.id})
end

# Send a message to a channel.
#
# channel - a string channel name (without '#')
# message - a string message
def send_message(channel, message)
  HTTP.post(INCOMING_URL, json: {
    username: "soundlikes",
    channel: "##{channel}",
    text: message
  })
end

def get_channel_name(channel_data)
  return @channels[channel_data] if @channels[channel_data]

  channel_response = HTTP.get("https://slack.com/api/channels.info",
                              params: {token: USER_TOKEN, channel: channel_data})
  channel_info = JSON.parse(channel_response.body)['channel']
  @channels[channel_data] = channel_info['name']
end

@rtmclient = SlackRTM::Client.new(websocket_url: RTM_URL)
@rtmclient.on(:message) do |data|
  if data["type"] == "message" && !data["hidden"]
    urls = data["text"].scan(/https:\/\/soundcloud\.com\/[^\/\s]+\/[^\/\s>]+/i)
    if urls.any?
      # set the group_id if not set yet and there's a group_url
      if @group_url && !@group_id && group = resolve_url(@group_id)
        @group_id = group.id
      end

      channel_name = get_channel_name(data['channel'])
      urls.each do |url|
        track = resolve_url(url)

        # contribute track to the group
        if track.kind == "track"
          contribute_to_group(@client, @group_id, track)
        end

        usernames = who_likes(track)
        if usernames.any?
          send_message(channel_name, "Liked by users: #{usernames.join(", ")}")
        else
          send_message(channel_name, "No one liked that track")
        end
      end
    elsif !(data["text"] =~ /\A\s*songs/).nil?
      channel_name = get_channel_name(data['channel'])
      send_message(channel_name, @group_url)
    end
  end
end
@rtmclient.main_loop

loop do
  sleep 1
end
