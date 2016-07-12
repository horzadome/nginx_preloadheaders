-- Copyright (C) 2016 Davor Grubisa
-- @author Davor Grubisa <horzadome@gmail.com>
-- Loosely based on logging module by Matthieu Tourne <matthieu@cloudflare.com>

-- Very ugly way of automatically setting "link" headers suited for http2 server push and browser link preload

local preloadheaders = {}
local module = preloadheaders

-- Just a helper increment function needed to count the hits for each resource
local function incr(dict, key, increment)
   increment = increment or 1
   local newval, err = dict:incr(key, increment)
   if err then
      dict:set(key, increment)
      newval = increment
   end
   return newval
end

function preloadheaders.add_hit(dict, key, value)
    local hit_count_key = key .. "-hit_count"
    local hit_uri_key = key .. "-hit_uri"

-- We need some sort of an UID in order to isolate various vhosts while allowing stuff to work across locations within the same vhost.
    local uid = ngx.var.scheme .. ngx.var.host
    uid = uid:gsub('%p', '')
    
    _G[uid.."test"] = "marko"
    
    
    
-- I've commented out all the logging functions. Uncomment them if you want nginx error log to show you what's going on.
    local debuglog ={}
    debuglog[#debuglog+1] = "\n==================== New Request ====================\n"
    debuglog[#debuglog+1] = "\nHOST IS "..uid
    debuglog[#debuglog+1] = "\nTest is IS ".._G[uid.."test"]

-- Here we count the hits
    local hit_uri = dict:get(hit_uri_key)
    if hit_uri then
    end

    if not hit_uri then
        local uri = string.gsub(ngx.var.request_uri, "?.*", "")
        dict:set(hit_uri_key, uri)
    end

    local hit_count = dict:get(hit_count_key) or 0

    local uri = string.gsub(ngx.var.request_uri, "?.*", "")

    if not hitmap then
        hitmap = {}
    end

    hitmap[uri] = hit_count
    incr(dict, hit_count_key)

-- Silly function to sort the array because lua can't do that on her own
    function spairs(t, order)
        -- collect the keys
        local keys = {}
        for k in pairs(t) do keys[#keys+1] = k end
        -- if order function given, sort by it by passing the table and keys a, b,
        -- otherwise just sort the keys 
        if order then
            table.sort(keys, function(a,b) return order(t, a, b) end)
        else
            table.sort(keys)
        end
        -- return the iterator function
        local i = 0
        return function()
            i = i + 1
            if keys[i] then
                return keys[i], t[keys[i]]
            end
        end
    end

    local arraytopreload = {}

    for k,v in spairs(hitmap, function(t,a,b) return t[b] < t[a] end) do
            table.insert(arraytopreload, k)
    end

    local i = 1
    local stufftopreload ={}
    local preloadhits = {};
    while i <= 10 do

        -- We are doing this if loop to prevent nginx from spitting out errors when it's restarted - while we don't know what to preload
        if arraytopreload[i] then
            local preloaduris = {}
            preloaduris[#preloaduris+1] = arraytopreload[i]
            preloaduri = table.concat(preloaduris);
--             debuglog[#debuglog+1]= "\nPreloaduris is !"..preloaduri.."!"
            
            if string.find(preloaduri, 'png$') then
                preloaduri = "<"..preloaduri..">; rel=preload; as=image,"
            end
            if string.find(preloaduri, 'css$') then
                preloaduri = "<"..preloaduri..">; rel=preload; as=style,"
            end
            if string.find(preloaduri, 'js$') then
                preloaduri = "<"..preloaduri..">; rel=preload; as=script,"
            end
--          debuglog[#debuglog+1]= "\nMatched it !"..preloaduri.."!"
                
            stufftopreload[#stufftopreload+1] = preloaduri    
            preloaduri =""

--          we need this to log hits in the error log
            preloadhits[#preloadhits+1] = preloaduri
            preloadhits[#preloadhits+1] = " "
            i = i + 1
        else i = i + 1
        end
    end

    -- we need this to log hits in the error log
    preloadhits = table.concat(preloadhits);
    stufftopreload = table.concat(stufftopreload);
    stufftopreload = string.gsub(stufftopreload,",$","")    
    
--     debuglog[#debuglog+1] = "\nPreload HITS is !"..preloadhits.."!"
--     debuglog[#debuglog+1] = "\nStuff to preload is !"..stufftopreload.."!"

    debuglog = table.concat(debuglog);
    ngx.log(ngx.ERR, "\n"..debuglog.."\n")

-- We're saving the resulting string in a shared dictionary so that we can use it elsewhere too
    dict:set("linkheader", stufftopreload)
end

-- safety net
local module_mt = {
   __newindex = (
      function (table, key, val)
         error('Attempt to write to undeclared variable "' .. key .. '"')
      end),
}

setmetatable(module, module_mt)

-- expose the module
return preloadheaders
