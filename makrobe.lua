#!/usr/local/bn/orbit
local orbit = require "orbit"
local ocash = require "orbit.cache"
local cjson  = require "cjson.safe" -- arf on error instead of barfing
local json = cjson.new() -- is thread safer
local convert, ratio, safe = json.encode_sparse_array(true)
json.encode_invalid_numbers = true -- avoid b00gs

module("makrobe", package.seeall, orbit.new)
package.path = package.path..";lib/?.lua;lib/?/?.lua"
local cache  = ocash.new(makrobe, cache_path)

require "luchia"
require "os"
local server = { host = "localhost", port = 5984, protocol = "http" }

local u      = require "util"
local io     = require "io"
--local crypto = require "crypto"
local utfhi = "\ufff0"

makrobe.not_found = function (web)
  web.status = "404 Not Found"
  return [[<html><head><title>Not Found</title></head>
  <body><p>Not found! Try harder you nit</p></body></html>]]
end                  
makrobe.server_error = function (web, msg)                                                                                  
  web.status = "500 Something died"
  io.stderr:write("G U R U M E D I A T I O N\n", msg, u.dump(web), "\n-- \n")
  msg = "Something died, sorry. Death is a natural part of life."
  return [[<html><head><title>Server Error</title></head>
  <body><pre>]] .. msg .. [[</pre></body></html>]]
end

local db = luchia.document:new("makrobe", server)

-- get the whole shebang as 
function get_users(web, ...) 
   local search = ...
   if search == "/users/" then
      search = nil
   end
   if search then
      if search:find("@") then
         resp = db:retrieve("_design/v/_view/email", { startkey='"'..search..'"', endkey='"'..search..utfhi..'"' })
      else
         resp = db:retrieve("_design/v/_view/name", { startkey='"'..search..'"', endkey='"'..search..utfhi..'"' })
      end
   else
      resp = db:retrieve("_design/v/_view/name")
   end
   return json.encode(resp)

end

function try_harder(web)
   web.status = 400
   --print("error on POST: "..json.encode(web.POST))
   return "Try harder"
end

--[[ FIXME: merge these records.. like in the perl

this creates new user
which inherits all from target,
and has transactions from source.
target should be old, source should be newer.

_id   47507ff0597f8eee8c726f1d7e71582e
_rev  14-e7265edbce56a152875a7bb5a36fc4d4
email  me@example.com
join_date 2010-01-01
name   Hans Rotvær
old_mail  "myoldmail@gmail.com"
approved  2010-01-01

bot 2
bot_giro  
indiv  4300
paid_200  9
paid_250  16

account  merge
0 26013257085
1 26011666395
card   

valid_from   2012-02-29
valid_to  2012-03-29
   --user.approved = os.date("%F")
transactions 

0
1

--]]
-- 
function merge_user(target, source)
   for k,v in source do
      if k == "name" or
         k == "approved" or
         k == "_id" or
         k == "_rev" or
         k == "join_date" or
         k == "old_mail" or
         k == "email" then
         -- preserve target
      elseif k == "indiv" or
         k == "bot" or k == "bot_giro" or
         k == "paid_200" or k == "paid_250" then
         -- sum target
         target[k] = target[k] + v
      elseif k == "valid_from" or
             k == "valid_to" then
         -- newer is better
         target[k] = v
      elseif k == "transactions" then
         target[k] = merge_xact(target.transactions, v)
      end
   end
   return target
end

-- fixme: maybe deduplicate transactions?
function merge_xact(to, from)
   for _,z in ipairs(from)  do
      table.push(to,z)
   end
   return to
end

function post_users(web, ...)
   local id = web.POST.id
   if not id then
      return try_harder(web)
   end
   local thing = db:retrieve(id)
   if not thing then
      return try_harder(web)
   end
   print(json.encode(web.POST))
   for k,v in pairs(web.POST) do
      thing[k] = v
   end
   local resp
   -- merge with existing entry if exists by email
   if web.POST.email and thing.email == "" then
      other = db:retrieve("_design/v/_view/email", { key = '"'..web.POST.email..'"' })
      if other then
         local merged = merge_xact(other, thing)
         resp = db:update(thing, id, thing._rev)
         print("merged: "..json.encode(resp))
         local delresp = db:delete(thing._id, thing._rev)
         print("deleted: "..json.encode(delresp))
         return resp
      else
         print("Didnt find merge target " .. web.POST.email)
      end
   end
   return db:update(thing, id, thing._rev)
end

function get_new(web, ...) 
   local resp = db:retrieve("_design/v/_view/new");
   return(json.encode(resp))
end

function post_user_accept(web, ...)
   local id = web.POST.id
   if not id then
      return try_harder(web)
   end
   local user = db:retrieve(id)
   if not user then
      return try_harder(web)
   end
   user.approved = os.date("%F")
   --print("ACCEPT "..user.email)
   return db:update(user, id, user._rev)
end
function post_user_deny(web, ...)
   local id = web.POST.id
   if not id then
      return try_harder(web)
   end
   local user = db:retrieve(id)
   if not user then
      return try_harder(web)
   end
   user.approved = "false"
   user.denied = os.date("%F")
   --print("DENY "..user.email)
   return db:update(user, id, user._rev)
end

function get_status(web, ...)
   local status = {}
   local resp = db:retrieve("_design/v/_view/new",{ limit = 0 });
   status.newcount = resp.total_rows
   resp = db:retrieve("",{ limit = 0 });
   status.allcount = resp.doc_count
   return json.encode(status)
end

makrobe:dispatch_post  (post_users, "/users/?")
makrobe:dispatch_post  (post_user_accept, "/user_accept/?")
makrobe:dispatch_post  (post_user_deny, "/user_deny/?")
makrobe:dispatch_get   (get_users, "/users/?", "/users/(.+)")
makrobe:dispatch_get   (get_new, "/newusers/?")
makrobe:dispatch_get   (get_status, "/status/?")


makrobe:dispatch_static("/css/.+")
makrobe:dispatch_static("/js/.+")
makrobe:dispatch_static("/img/.+")
makrobe:dispatch_static("/index\.html")

return _M


