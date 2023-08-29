# frozen_string_literal: true

# Check if the provided value(s) is an IPv4/IPv6/either address.
#
# Puppet used to have validate_ and is_ functions for IPv4 and IPv6, but they
# deprecated them without providing functioning replacements (for Puppet 3.7).
#

require 'ipaddr'

Puppet::Functions.create_function(:is_ipaddr) do |args|
  err('Invalid use of function is_ipaddr') if args.empty? or args.size > 2

  addr = args[0]
  ipver = args[1]

  addr = [addr] if addr.instance_of? String

  unless addr.instance_of? Array
    err("First argument to is_ipaddr is not a string or array: #{addr}")
    return false
  end

  if args.size == 2 and !ipver.is_a? Integer
    err("Second argument to is_ipaddr is not an integer: #{ipver}")
    return false
  end

  addr.each do |this|
    this_addr = begin
      IPAddr.new(this)
    rescue StandardError
      false
    end
    unless this_addr
      debug("#{this} is not an IP address")
      return false
    end

    if ipver == 4 and !this_addr.ipv4?
      debug("#{this} is not an IPv4 address")
      return false
    end

    if ipver == 6 and !this_addr.ipv6?
      debug("#{this} is not an IPv6 address")
      return false
    end
  end

  debug("All inputs #{addr} found to be IP (#{ipver}) address(es).")
  return true
end
