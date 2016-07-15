# nginx_preloaders
nginx lua module for automatically determining resources which should be added to "Link" http header in order for web browsers to preload them. In case the server is behind an http/2 Server Push capable proxy (such as CloudFlare), the proxy will actually push those resources without the clients even requesting them (read more about it at the bottom of this Readme).

## Results may vary
* I haven't benchmarked this on high-traffic or large-vhost servers, so no idea if it will blow up there
* Like any other optimization, it varies depending on the use case. It will most probably improve user experience, and I don't see how it should hinder it. However, you should measure it before launching to production.

## Usage

* Load the module in nginx's **http** section (nginx.conf)
```Nginx
lua_package_path    "/etc/nginx/lua-modules/?.lua;;";
lua_shared_dict     log_dict    1M;
```
* Add the logging snippet in the location which you want to track. I.e. you'll probably only want to track your static resource usage, so best add it to your static resource section if you have one. Otherwise, add it to your location /
```Nginx
log_by_lua_block {
    local preloadheaders = require("preloadheaders")
    local hit_uri = string.gsub(ngx.var.request_uri, "?.*", "")
    preloadheaders.add_hit(ngx.shared.preloadheaders, hit_uri, hit_uri)
}     
```
* Add the rewrite snippet in the location which should have Link header added. I.e. your index file or your location /
```Nginx
rewrite_by_lua_block {
    local uid = ngx.var.scheme .. ngx.var.host
    uid = uid:gsub('%p', '')
    local content_type = ngx.header.content_type
    ngx.header.content_type = content_type
    local linkuid = "link_" .. uid
    ngx.header.Link = ngx.shared.preloadheaders:get(linkuid)
}
```
And that's it !

### Usage Help Examples
If you don't have a separate static resource section, you'll want your / location to look something like this:
```Nginx
location / {
    index index.html /index.html;
    root   /var/www/example.com;

    log_by_lua_block {
        local preloadheaders = require("preloadheaders")
        local hit_uri = string.gsub(ngx.var.request_uri, "?.*", "")
        preloadheaders.add_hit(ngx.shared.preloadheaders, hit_uri, hit_uri)
    }                                                                              
           
    rewrite_by_lua_block {
        local uid = ngx.var.scheme .. ngx.var.host
        uid = uid:gsub('%p', '')
        local content_type = ngx.header.content_type
        ngx.header.content_type = content_type
        local linkuid = "link_" .. uid
        ngx.header.Link = ngx.shared.preloadheaders:get(linkuid)
    }
}	
```

In case you do have a static resource section, you can split it up, so that only static resource usage is tracked and Link header added to everything other than static resources !

```Nginx
location ~* ^.+.(jpg|jpeg|gif|png|ico|js|css|exe|bin|gz|zip|rar|7z|pdf)$ {
    root   /var/www/example.com;
    log_by_lua_block {
        local preloadheaders = require("preloadheaders")
        local hit_uri = string.gsub(ngx.var.request_uri, "?.*", "")
        preloadheaders.add_hit(ngx.shared.preloadheaders, hit_uri, hit_uri)
    }    
}
location / {
    index index.html /index.html;
    root   /var/www/example.com;
    rewrite_by_lua_block {
        local uid = ngx.var.scheme .. ngx.var.host
        uid = uid:gsub('%p', '')
        local content_type = ngx.header.content_type
        ngx.header.content_type = content_type
        local linkuid = "link_" .. uid
        ngx.header.Link = ngx.shared.preloadheaders:get(linkuid)
    }
}	
```

## Preload introduction
There's 2 concepts to understand before going into preloading.
1) The preload keyword on link elements (as in html head "link" element) https://www.w3.org/TR/preload/#dfn-preload-link
2) Link header (as in http header which can be used to designate resources which need to be preloaded)
3) HTTP/2 Server Push as in sending resources to clients before they even ask for them https://www.w3.org/TR/preload/#server-push-http-2

This nginx module focuses on the 2nd - http "Link" header

When enabled, this module will track resource usage; i.e. png, css, js that's sent to clients visiting a specific site (vhost), and it will add http "Link" header to subsequential resources for that site.

A typical use case would be to enable logging of image, script and stylesheet usage, and then based on that append a http "Link" header to html pages.

Once we have a "Link" header on all the html pages, and that header contains references to resources which need to be preloaded, browsers start doing their magic by fetching those resources before your css or js files are even parsed, so they're ready in browser's cache when they're needed.
Or in case of http/2 proxy, such as CloudFlare, it reads the "Link" header and initiates a server push of those resources as soon as it's done sending the initial response to the client - before the browser even finishes rendering the page.
All of this is non-blocking and happens in the background, so it can not hinder web page loading or rendering time - it can only improve it.

In case of http/1.1 server, when the inital response (i.e. index.php) is downloaded to the browser, browser will immediately start downloading all the resources defined in the "Link" header. In browser's dev console, you'll see that the initiator for a preloaded resource is i.e. "index.html:1". Meaning line 1 in index.html . 
Compared to non-preloaded resource, whose initiator will be i.e. jquery.min.js:333 , meaning that the browser had to parse the entire index page, download jquery.min.js and interpret that script to even start loading the resource in question. With preload, it's done as soon as first response's headers hit the browser.

In case of http/2 server, the server will actually initiate a server push immediately after the initial response, so the browser doesn't even have to request the resource to have it. This saves us an additional rtt. In browser's dev console, you'll notice that the initiator was http/2 Server Push.

In case your server doesn't support HTTP2 Server Push technology, try CloudFlare(tm). It's free and totally awesome. Just enable SSL (yeah, that's free too) and you'll get http2 including server push automatically.

### A bit about HTTP/2 Server Push Technology

"HTTP/2 allows a server to pre-emptively send (or "push") responses (along with corresponding "promised" requests) to a client in association with a previous client-initiated request. This can be useful when the server knows the client will need to have those responses available in order to fully process the response to the original request."*

Meaning that as soon as the server sends out the initial reply (first html response), it can immediately start sending all the javascripts, css and images which will be needed to render that page. Standard behavior is to just send the html page and then wait for the browser to parse it and start requesting all the additional resources.
By pushing those resources immediately after the initial html is sent, we are completely skipping over the process of waiting for the client to receive the initial html, parse it and submit requests for other resources which are needed to render that page anyways. By the time client is done parsing the initial html, his cache already contains at the very least some of the css and javascript, and sometimes everything so no subsequent requests are even needed !

Additionally, we can use server push features to "preheat" browser's cache, much like we would if we used html's "link rel=preload" feature.
If we, for example know that the client is going to open our i.e. image gallery, we can pre-emptively send all the js, css and images that this gallery needs, so when the client actually clicks it, it's lightning-fast because everything is already downloaded and cached.
