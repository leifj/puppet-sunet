# Get eduroam
class sunet::geteduroam(
  String $domain,
  String $realm,
  Hash $customers = {},
  Array $resolvers = [],
  Boolean $app = true,
  Boolean $radius = true,
  Boolean $ocsp = true,
  String $app_tag = 'latest',
  String $freeradius_tag = 'latest',
  String $ocsp_tag = 'latest',
  String $haproxy_tag = '3.0.2',
  Array $app_admins = [],
  Boolean $qa_federation = false,
){

  ensure_resource('sunet::misc::create_dir', '/opt/geteduroam/config', { owner => 'root', group => 'root', mode => '0750'})
  ensure_resource('sunet::misc::create_dir', '/opt/geteduroam/cert', { owner => 'root', group => 'root', mode => '0755'})

  $db_servers = lookup('mariadb_cluster_nodes', Array, undef, [])
  file { '/opt/geteduroam/haproxy.cfg':
    content => template('sunet/geteduroam/haproxy.cfg.erb'),
    mode    => '0755',
  }

  if $radius {
    sunet::nftables::allow { 'expose-allow-radius':
      from  => lookup('radius_servers', undef, undef,['192.36.171.226', '192.36.171.227', '2001:6b0:8:2::226', '2001:6b0:8:2::227'] ),
      port  => 1812,
      proto =>  'udp'
    }

    require sunet::certbot::sync::client::dirs
    file { '/opt/certbot-sync/renewal-hooks/deploy/geteduroam':
      ensure  => file,
      mode    => '0700',
      content => file('sunet/geteduroam/certbot-renewal-hook'),
    }

    $shared_secret = lookup('shared_secret', undef, undef, undef)
    file { '/opt/geteduroam/config/clients.conf':
      content => template('sunet/geteduroam/clients.conf.erb'),
      mode    => '0755',
    }
  }
  if $app {
    ensure_resource('sunet::misc::create_dir', '/opt/geteduroam/var', { owner => 'root', group => 'www-data', mode => '0770'})

    # Ugly workaround since nunoc-ops install the class on all machines
    if $facts['networking']['fqdn'] != 'get-app-1.test.eduroam.se' {
      sunet::ici_ca::rp { 'infra': }
    }

    file {'/etc/ssl/private/infra.pem':
      ensure => 'link',
      target => "/etc/ssl/private/${facts['networking']['fqdn']}_infra.pem"
    }

    file {'/etc/ssl/private/infra.key':
      ensure => 'link',
      target => "/etc/ssl/private/${facts['networking']['fqdn']}_infra.key"
    }

    if lookup('saml_metadata_key', undef, undef, undef) != undef {
      sunet::snippets::secret_file { '/opt/geteduroam/cert/saml.key': hiera_key => 'saml_metadata_key', group =>  'www-data',  mode  => '0750', }
      # assume cert is in cosmos repo
    } else {
      # make key pair
      sunet::snippets::keygen {'saml_metadata_key':
        key_file  => '/opt/geteduroam/cert/saml.key',
        cert_file => '/opt/geteduroam/cert/saml.pem',
      }
    }

    file { '/opt/geteduroam/config/letswifi.conf.php':
      content => template('sunet/geteduroam/letswifi.conf.simplesaml.php.erb'),
      mode    => '0755',
    }
    file { '/opt/geteduroam/config/config.php':
      content => template('sunet/geteduroam/config.php.erb'),
      mode    => '0755',
    }
    file { '/opt/geteduroam/config/authsources.php':
      content => template('sunet/geteduroam/authsources.php.erb'),
      mode    => '0755',
    }

    if $qa_federation {
      file { '/opt/geteduroam/cert/swamid.crt':
        content => file('sunet/geteduroam/swamid-qa.crt'),
        mode    => '0755',
        }
    } else {
      file { '/opt/geteduroam/cert/swamid.crt':
        content => file('sunet/geteduroam/md-signer2.crt'),
        mode    => '0755',
        }
    }
    sunet::nftables::allow { 'expose-allow-http':
      from => 'any',
      port => 80,
    }
    sunet::nftables::allow { 'expose-allow-https':
      from => 'any',
      port => 443,
    }
  }

  if $ocsp {
      file { '/opt/geteduroam/config/eap.conf':
        content => template('sunet/geteduroam/eap.conf.erb'),
        mode    => '0755',
        }

  }

  sunet::docker_compose { 'geteduroam':
    content          => template('sunet/geteduroam/docker-compose.yml.erb'),
    service_name     => 'geteduroam',
    compose_dir      => '/opt/',
    compose_filename => 'docker-compose.yml',
    description      => 'geteduroam',
  }

}
