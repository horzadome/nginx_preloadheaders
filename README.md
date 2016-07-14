# nginx_preloaders
nginx lua module for automatically determining resources which should be added to "Link" http header in order for web browsers to preload them or push them in the initial response ( http/2 server push )

# Don't use this module yet
This is work in progress and does **NOT** work as advertised
* I haven't benchmarked it yet, so no idea if it will blow up on production servers
* It's debugging by default, meaning it constantly spits stuff up in vhost's error.log
* I don't know lua and don't know programming, so this is a perfect example of code you don't want anywhere near you

## Usage

* Load the module in nginx's **http** section (nginx.conf)
```Nginx
lua_package_path    "/etc/nginx/lua-modules/?.lua;;";
lua_shared_dict     log_dict    1M;
```
* Add the logging snippet in the location which you want to track. I.e. you'll probably only want to track your static resource usage, so best add it to your static resource section if you have one. Otherwise, add it to your location /
```Nginx
log_by_lua '
    local preloadheaders = require("preloadheaders")
    local hit_uri = string.gsub(ngx.var.request_uri, "?.*", "")
    preloadheaders.add_hit(ngx.shared.log_dict, hit_uri, hit_uri)
';
```
* Add the rewrite snippet in the location which should have Link header added. I.e. your index file or your location /
```Nginx
rewrite_by_lua '
   local content_type = ngx.header.content_type
   ngx.header.content_type = content_type
   ngx.header.Link = ngx.shared.log_dict:get("linkheader")
';
```
And that's it !

## Usage Help Examples
If you don't have a separate static resource section, you'll want your / location to look something like this:
```Nginx
location / {
    index index.html /index.html;
    root   /var/www/example.com;

    log_by_lua '
         local preloadheaders = require("preloadheaders")
         local hit_uri = string.gsub(ngx.var.request_uri, "?.*", "")
         preloadheaders.add_hit(ngx.shared.log_dict, hit_uri, hit_uri)
    ';
    rewrite_by_lua '
         local content_type = ngx.header.content_type
         ngx.header.content_type = content_type
         ngx.header.Link = ngx.shared.log_dict:get("linkheader")
    ';
}	
```

In case you do have a static resource section, you can split it up, so that only static resource usage is tracked and Link header added to everything other than static resources !

```Nginx
location ~* ^.+.(jpg|jpeg|gif|png|ico|js|css|exe|bin|gz|zip|rar|7z|pdf)$ {
    root   /var/www/example.com;
    log_by_lua '
         local preloadheaders = require("preloadheaders")
         local hit_uri = string.gsub(ngx.var.request_uri, "?.*", "")
         preloadheaders.add_hit(ngx.shared.log_dict, hit_uri, hit_uri)
    ';    
}
location / {
    index index.html /index.html;
    root   /var/www/example.com;
    rewrite_by_lua '
         local content_type = ngx.header.content_type
         ngx.header.content_type = content_type
         ngx.header.Link = ngx.shared.log_dict:get("linkheader")
    ';
}	
```
