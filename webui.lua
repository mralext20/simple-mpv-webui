local socket = require("socket")
require 'mp.options'
require 'mp.msg'

local msg_prefix = "[webui] "

local options = {
  port = 8080,
  disable = false,
  logging = false,
}
read_options(options, "webui")

local function validate_number_param(param)
  if not tonumber(param) then
    return false, 'Parameter needs to be an integer or float'
  else
    return true, nil
  end
end

local commands = {
  play = function()
    return pcall(mp.set_property_bool, "pause", false)
  end,

  pause = function()
    return pcall(mp.set_property_bool, "pause", true)
  end,

  toggle_pause = function()
    local curr = mp.get_property_bool("pause")
    return pcall(mp.set_property_bool, "pause", not curr)
  end,

  fullscreen = function()
    local curr = mp.get_property_bool("fullscreen")
    return pcall(mp.set_property_bool, "fullscreen", not curr)
  end,

  seek = function(t)
    local valid, msg = validate_number_param(t)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, "seek "..t)
  end,

  set_position = function(t)
    local valid, msg = validate_number_param(t)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, "seek "..t.." absolute")
  end,

  playlist_prev = function()
    local position = tonumber(mp.get_property("time-pos"))
    if position > 1 then
      return pcall(mp.command, "seek "..-position)
    else
      return pcall(mp.command, "playlist-prev")
    end
  end,

  playlist_next = function()
    return pcall(mp.command, "playlist-next")
  end,

  add_volume = function(v)
    local valid, msg = validate_number_param(v)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, 'add volume '..v)
  end,

  set_volume = function(v)
    local valid, msg = validate_number_param(v)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, 'set volume '..v)
  end,

  add_sub_delay = function(ms)
    local valid, msg = validate_number_param(ms)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, 'add sub-delay '..ms)
  end,

  set_sub_delay = function(ms)
    local valid, msg = validate_number_param(ms)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, 'set sub-delay '..ms)
  end,

  add_audio_delay = function(ms)
    local valid, msg = validate_number_param(ms)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, 'add audio-delay '..ms)
  end,

  set_audio_delay = function(ms)
    local valid, msg = validate_number_param(ms)
    if not valid then
      return true, false, msg
    end
    return pcall(mp.command, 'set audio-delay '..ms)
  end,

  cycle_sub = function()
    return pcall(mp.command, "cycle sub")
  end,

  cycle_audio = function()
    return pcall(mp.command, "cycle audio")
  end,

  cycle_audio_device = function()
    return pcall(mp.command, "cycle_values audio-device alsa alsa/hdmi")
  end
}

local function get_content_type(file_type)
  if file_type == 'html' then
    return 'text/html; charset=UTF-8'
  elseif file_type == 'json' then
    return 'application/json; charset=UTF-8'
  elseif file_type == 'js' then
    return 'application/javascript; charset=UTF-8'
  elseif file_type == 'png' then
    return 'image/png'
  elseif file_type == 'ico' then
    return 'image/x-icon'
  elseif file_type == 'svg' then
    return 'image/svg+xml'
  elseif file_type == 'xml' then
    return 'application/xml; charset=UTF-8'
  elseif file_type == 'css' then
    return 'text/css; charset=UTF-8'
  elseif file_type == 'woff2' then
    return 'font/woff2; charset=UTF-8'
  elseif file_type == 'mp3' then
    return 'audio/mpeg'
  end
end

local function header(code, content_type)
  local close = '\nConnection: close\n\n'
  local cors = '\nAccess-Control-Allow-Origin: *\n'
  if code == 200 then
    return 'HTTP/1.1 200 OK'..cors..'Content-Type: '..content_type..close
  elseif code == 400 then
    return 'HTTP/1.1 400 Bad Request'..cors..close
  elseif code == 401 then
    return 'HTTP/1.1 401 Unauthorized\n'..cors..'WWW-Authenticate: Basic realm="Simple MPV WebUI"'..close
  elseif code == 404 then
    return 'HTTP/1.1 404 Not Found'..cors..close
  elseif code == 405 then
    return 'HTTP/1.1 405 Method Not Allowed'..cors..close
  elseif code == 503 then
    return 'HTTP/1.1 503 Service Unavailable'..cors..close
  end
end

local function round(a)
  return (a - a % 1) / 1
end

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

local function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

local function file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

local function lines_from(file)
  if not file_exists(file) then return {} end
  local lines = {}
  for line in io.lines(file) do
    lines[#lines + 1] = line
  end
  return lines
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end

local function dec64(data)
  local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  data = string.gsub(data, '[^'..b..'=]', '')
  return (data:gsub('.', function(x)
    if (x == '=') then return '' end
      local r,f='',(b:find(x)-1)
      for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
      return r;
  end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
    if (#x ~= 8) then return '' end
    local c=0
    for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
    return string.char(c)
  end))
end

local function log_line(headers, code)
  if not options.logging then
    return
  end

  local referer = headers['referer'] or '-'
  local agent = headers['agent'] or '-'
  local time = os.date('%d/%b/%Y:%H:%M:%S %z', os.time())
  mp.msg.info(
    headers["clientip"]..' - - ['..time..'] "'..headers['request']..'" '..code..' - "'..referer..'" "'..agent..'"')
end

local function build_json_response()
  local metadata = mp.get_property("metadata")
  if metadata == nil then
    return false
  else
    return '{"file":"'..mp.get_property('filename')..'",' ..
            '"duration":"'..round(mp.get_property("duration"))..'",' ..
            '"position":"'..round(mp.get_property("time-pos"))..'",' ..
            '"pause":"'..mp.get_property("pause")..'",' ..
            '"remaining":"'..round(mp.get_property("playtime-remaining"))..'",' ..
            '"sub-delay":"'..mp.get_property_osd("sub-delay")..'",' ..
            '"audio-delay":"'..mp.get_property_osd("audio-delay")..'",' ..
            '"metadata":'..metadata..',' ..
            '"volume":"'..round(mp.get_property("volume"))..'",' ..
            '"volume-max":"'..round(mp.get_property("volume-max"))..'"}'
  end
end

local function handle_post(path)
  local components = string.gmatch(path, "[^/]+")
  local api_prefix = components()
  if api_prefix ~= 'api' then
    return 404, nil, nil
  end
  local command = components()
  local param = components() or ""

  local f = commands[command]
  if f ~= nil then
    local status, err, ret = f(param)
    if err then
      return 200, get_content_type('json'), '{"message": "success"}'
    else
      return 400, get_content_type('json'), '{"message": "'..ret..'"}'
    end
  else
    return 404, nil, nil
  end
end

local function handle_status_get()
  local json = build_json_response()
  if not json then
    return 503, nil, nil
  else
    return 200, get_content_type("json"), json
  end
end

local function handle_static_get(path)
  if string.find(path, '%.%./') then
    return nil, nil
  end
  if path == "" then
    path = 'index.html'
  end

  local content = read_file(script_path()..'webui-page/'..path)
  local extension = path:match("[^.]+$") or ""
  local content_type = get_content_type(extension)
  if content == nil or content_type == nil then
    return 404, nil, nil
  else
    return 200, content_type, content
  end
end

local function is_authenticated(headers, passwd)
  if not headers['user'] or not headers['password'] then
    return false
  end
  for k,line in pairs(passwd) do
    if line == headers['user']..':'..headers['password'] then
      return true
    end
  end
  return false
end

local function handle_request(headers, passwd)
  if passwd ~= nil then
    if not is_authenticated(headers, passwd) then
      return 401, nil, nil
    end
  end
  if headers["method"] == "POST" then
    return handle_post(headers['path'])

  elseif headers["method"] == "GET" then
    if headers["path"] == "api/status" or headers["path"] == "api/status/" then
      return handle_status_get()

    else
      return handle_static_get(headers["path"])
    end
  else
    return 405, nil, nil
  end
end

local function parse_request(connection)
  local headers = {}
  headers['clientip'] = connection:getpeername()
  while true do
    local line = connection:receive()
    if line == nil or line == "" then
      break
    end
    if not headers['request'] then
      local request = string.gmatch(line, "%S+")
      headers["request"] = line
      headers["method"] = request()
      headers["path"] = string.sub(request(), 2)
    end
    if string.starts(line, "User-Agent") then
      headers["agent"] = string.sub(line, 13)
    elseif string.starts(line, "Referer") then
      headers["referer"] = string.sub(line, 10)
    elseif string.starts(line, "Authorization: Basic ") then
      local auth64 = string.sub(line, 22)
      local auth_components = string.gmatch(dec64(auth64), "[^:]+")
      headers["user"] = auth_components()
      headers["password"] = auth_components()
    end
  end
  return headers
end

local function listen(server, passwd)
  local connection = server:accept()
  if connection == nil then
    return
  end

  local headers = parse_request(connection)
  local code, content_type, content = handle_request(headers, passwd)

  connection:send(header(code, content_type))
  if content then
    connection:send(content)
  end
  connection:close()
  log_line(headers, code)
  return
end

local function get_passwd()
  if file_exists(script_path()..".htpasswd") then
    mp.msg.info('Found .htpasswd file. Basic authentication is enabled.')
    return lines_from(script_path()..".htpasswd")
  end
end

local function init_server()
  local host = "0.0.0.0"

  local server = socket.bind(host, options.port)

  return server
end

if options.disable then
  mp.osd_message(msg_prefix.."disabled", 2)
  return
else
  local server = init_server()
  if server == nil then
    mp.msg.error("Error: couldn't spawn server on port "..options.port)
  else
    mp.osd_message(msg_prefix.."serving on port "..options.port, 2)
    server:settimeout(0)
    local passwd = get_passwd()
    mp.add_periodic_timer(0.2, function() listen(server, passwd) end)
  end
end
