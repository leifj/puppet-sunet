# Run bankid-idp with compose
class sunet::bankidp(
  String $instance,
  Array $environments_extras = [],
  Array $resolvers = [],
  Array $volumes_extras = [],
  Array $ports_extras = [],
  String $imagetag='latest',
  String $tz = 'Europe/Stockholm',
  String $bankid_home = '/opt/bankidp',
  String $spring_config_import = '/config/service.yml',
  String $service_name = 'bankidp.qa.swamid.se',
  Boolean $prod = true,
  Boolean $app_node = false,
  Boolean $redis_node = false,
) {

  $apps = $facts['bankid_cluster_info']['apps']
  $redises = $facts['bankid_cluster_info']['redises']

  sunet::ici_ca::rp { 'infra': }

  if $app_node {

    ensure_resource('sunet::misc::create_dir', '/opt/bankidp/credentials/', { owner => 'root', group => 'root', mode => '0750'})
    $customers = lookup('bankidp_customers', undef, undef, undef)
    sort(keys($customers)).each |$name| {
      sunet::snippets::secret_file { "${bankid_home}/credentials/${name}.key": hiera_key => "bankidp_customers.${name}.key" }
      $password = lookup("bankidp_customers.${name}.password", undef, undef, undef)
      exec { "build_${name}.p12":
        command => "openssl pkcs12 -export -in /opt/bankidp/credentials/${name}.pem -inkey /opt/bankidp/credentials/${name}.key -name '${name}-bankid' -out /opt/bankidp/credentials/${name}.p12 -passin pass:${password} -passout pass:qwerty123",
        onlyif  => "test ! -f ${bankid_home}/credentals/${name}.p12"
      }
    }

    exec { 'infra.p12':
      command => 'openssl pkcs12 -export -in /etc/ssl/certs/infra.crt -nokeys -name infra -out /etc/ssl/certs/infra.p12  -passout pass:qwerty123',
      onlyif  => 'test ! -f /etc/ssl/certs/infra.p12'
    }

    exec { "${facts['networking']['fqdn']}_infra.p12":
      command => "openssl pkcs12 -export -in /etc/ssl/certs/${facts['networking']['fqdn']}_infra.crt -inkey /etc/ssl/private/${facts['networking']['fqdn']}_infra.pem -name 'infra' -out /etc/ssl/private/${facts['networking']['fqdn']}_infra.p12 -passout pass:qwerty123",
      onlyif  => "test ! -f /etc/ssl/private/${facts['networking']['fqdn']}_infra.p12"
    }

    class { 'sunet::frontend::register_sites':
      sites => {
        $service_name => {
          frontends => ['se-fre-lb-1.sunet.se', 'se-tug-lb-1.sunet.se'],
          port      => '443',
        }
      }
    }
    ensure_resource('sunet::misc::create_dir', '/opt/bankidp/config/', { owner => 'root', group => 'root', mode => '0750'})
    file { '/opt/bankidp/config/service.yml':
      content => template('sunet/bankidp/service.yml.erb'),
      mode    => '0755',
    }

    $signing_cert = $prod ? {
      true => 'md-signer2.crt',
      false => 'swamid-qa.crt',
    }

    file { "/opt/bankidp/config/certificates/${signing_cert}":
      ensure  => 'file',
      mode    => '0755',
      owner   => 'root',
      content => file("sunet/bankidp/${signing_cert}")
    }

    sunet::docker_compose { 'bankidp':
      content          => template('sunet/bankidp/docker-compose-bankid-idp.yml.erb'),
      service_name     => 'bankidp',
      compose_dir      => '/opt/',
      compose_filename => 'docker-compose.yml',
      description      => 'Freja ftw',
    }
  }
  if $redis_node {
    class { 'sunet::rediscluster':
      numnodes => 2,
      hostmode => true,
      tls      => true
    }
  }
}
