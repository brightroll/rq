#!/usr/bin/env ruby

# DN
# This was just me testing that the resolv-replace does a proper
# round robin when using Net::HTTP to a name that returns multiple
# A records
#
require 'net/http'
require 'uri'
require 'fileutils'
require 'fcntl'
require 'digest'
require 'resolv-replace'

uri = URI.parse('http://barrier-v03.btrll.com:3333/')

response = Net::HTTP.get_response(uri)

if response.body.match /<td>\s+?<a href="http:\/\/([^"]+):/m
  #p $&
  p $+
end
#p response.body
