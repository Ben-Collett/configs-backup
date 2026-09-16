-- skips sing/songs track and picks first subtitle past it if one is avaliable
-- will change the track even if resuming playback
-- if no other candidates are found the sign/songs will still be used.
local function should_skip(sub_track)
  title = sub_track.title
  title = title:lower()
  return title:find("signs/songs")
end


-- converts a track object to a string for debugging and logging purposes
local function track_to_str(track)
    return string.format("[%s] id=%s type=%s title=%q lang=%q forced=%s",
    track.type, tostring(track.id), track.type, title, tostring(track.lang), tostring(track.forced))
end


local call_count =0

-- mp allows you to access mpvs scripting api
-- observe property listens for a proprty to change
-- track list listens to the sub, audio and video tracks
-- the call_count exist because the first track call the list isn't intalized so it must be skipped
-- as the selected track cannot be changed on the first call, I think, I couldn't really find any information that's just what I observed
-- and subsequent calls besides the first call after the tracks are intilized and changable should be ignored
-- native means a native lua object instead of json
mp.observe_property("track-list","native",function(_,tracks)
  -- in case it's nill some how I don't know how these parameters work
  if not tracks then return end
  if call_count>1 then
    return
  end
  call_count +=1

  for _, track in ipairs(tracks) do
    -- skip any non-subtitle tracks, ~= means not equal
    -- the other types are audio and video
    if track.type ~= "sub" then
      continue
    end

    if not should_skip(track) then
      -- comment out the line below if you want to hide when track is being changed.
      mp.msg.info("setting subtitle track to ".. track_to_str(track))

      -- sid = subtitle track id
      mp.set_property("sid",track.id)

      break

    end
  end

end)
