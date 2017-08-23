require stdlib
require concat

class sunet::ssh_keyscan {
   exec {'ssh-keyscan':
      command     => 'touch /etc/ssh/ssh_known_hosts.scan && ssh-keyscan -t rsa,dsa,ecdsa,ed25519 -f /etc/ssh/sunet_keyscan_hosts.txt | sort -u - /etc/ssh/ssh_known_hosts.scan | diff -u /etc/ssh/ssh_known_hosts.scan - | patch -p0 /etc/ssh/ssh_known_hosts.scan',
      creates     => '/etc/ssh/ssh_known_hosts.scan'
   }
   file {'/etc/ssh/ssh_known_hosts':
      ensure      => present,
      source      => '/etc/ssh/ssh_known_hosts.scan',
      require     => Exec['ssh-keyscan']
   }
   concat {"/etc/ssh/sunet_keyscan_hosts.txt":
      owner  => root,
      group  => root,
      mode   => '0644',
      notify => File['/etc/ssh/ssh_known_hosts']
   }
   concat::fragment {"/etc/ssh/sunet_keyscan_hosts.txt_header":
      target  => "/etc/ssh/sunet_keyscan_hosts.txt",
      content => "# do not edit by hand - maintained by sunet::ssh_keyscan\n",
      order   => '10',
      notify  => File['/etc/ssh/ssh_known_hosts']
   }
}

define sunet::ssh_keyscan::host ($aliases = [], $address = undef) {
   ensure_resource('class','sunet::ssh_keyscan',{})
   $the_address = $address ? {
      undef   => dnsLookup($title),
      default => [$address]
   }
   validate_array($the_address)
   $the_aliases = concat(any2array($aliases),[$title],[$the_address])
   concat::fragment {"${title}_sunet_keyscan":
      target  => "/etc/ssh/sunet_keyscan_hosts.txt",
      content => inline_template("<%= the_address[0] %> <%= the_aliases.join(',') %>\n"),
      order   => '20',
      notify  => Exec['ssh-keyscan']
   }
}
