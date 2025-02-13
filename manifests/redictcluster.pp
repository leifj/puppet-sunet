# A cluster class
class sunet::redictcluster(
  Integer $numnodes = 3,
  Boolean $hostmode = false,
  Optional[Boolean] $tls = false,
  Optional[String] $cluster_announce_ip = '',
  Optional[Boolean] $automatic_rectify = false,
  Optional[Boolean] $prevent_reboot = false,
  Optional[String] $image = 'registry.redict.io/redict',
  Optional[String] $tag = '7-bookworm',
  Optional[String] $maxmemory = undef,
  String $maxmemory_policy = 'noeviction',
)
{

  $fqdn = $facts['networking']['fqdn']
  # Allow the user to either specify the variable in cosmos-rules or in hiera
  if $cluster_announce_ip == '' {
    $__cluster_announce_ip = lookup('cluster_announce_ip', undef, undef, '')
  } else {
    $__cluster_announce_ip = $cluster_announce_ip
  }
  # Allow the user to use the explicit string ipaddress or ipaddress6 to use the corresponding facts
  if $__cluster_announce_ip == 'ipaddress' {
    $_cluster_announce_ip = $facts['networking']['ip']
  } elsif $__cluster_announce_ip == 'ipaddress6' {
    $_cluster_announce_ip = $facts['networking']['ip6']
  } else {
    $_cluster_announce_ip = $__cluster_announce_ip
  }

  $redict_password = safe_hiera('redict_password')

  if $tls {
    file { "/etc/ssl/certs/${fqdn}_infra.crt":
      mode   => '0644',
    }

    file { "/etc/ssl/private/${fqdn}_infra.key":
      mode   => '0644',
    }

    file { '/etc/ssl/private':
      mode   => '0711',
    }
  }

  sunet::docker_compose { 'redictcluster_compose':
    content          => template('sunet/redictcluster/docker-compose.yml.erb'),
    service_name     => 'redict',
    compose_dir      => '/opt/',
    compose_filename => 'docker-compose.yml',
    description      => 'redict Cluster',
  }
  file {'/etc/sysctl.d/55-vm-overcommit.conf':
    ensure  => present,
    content => template('sunet/redictcluster/55-vm-overcommit.conf.erb'),
  }
  file {'/opt/redict-rectify.sh':
    ensure  => present,
    mode    => '0755',
    content => template('sunet/redictcluster/redict-rectify.sh.erb'),
  }
  if $automatic_rectify {
    sunet::scriptherder::cronjob { 'redict-rectify':
      cmd           => '/opt/redict-rectify.sh',
      hour          => '*',
      minute        => '*/10',
      ok_criteria   => ['exit_status=0','max_age=2d'],
      warn_criteria => ['exit_status=1','max_age=3d'],
    }
  }

  if $prevent_reboot {
    include sunet::packages::cowsay
    file {'/etc/molly-guard/run.d/11-redictcluster':
      ensure  => present,
      mode    => '0755',
      content => template('sunet/redictcluster/11-redictcluster.erb'),
    }
  }

  range(0, $numnodes - 1).each |$i|{
    $clusterportnum = 16379 + $i
    $redictportnum = 6379 + $i

    file { "/opt/redict/node-${i}":
      ensure => directory,
      owner  => '999',
      group  => '999',
    }
    -> file { "/opt/redict/node-${i}/server.conf":
      ensure  => present,
      content => template('sunet/redictcluster/server.conf.erb'),
    }
    if $::facts['sunet_nftables_enabled'] == 'yes' or $::facts['dockerhost_advanced_network'] == 'yes' or $::facts['dockerhost2'] == 'yes' {
      $ports = [$redictportnum, $clusterportnum]
      $ports.each|$port| {
        sunet::nftables::rule { "redict_port_${port}":
          rule => "add rule inet filter input tcp dport ${port} counter accept comment \"allow-redict-${port}\""
        }
      }
    } else {
      sunet::misc::ufw_allow { "redict_port_${i}_v6":
        from => '::/0',
        port => [$redictportnum,$clusterportnum],
      }
      sunet::misc::ufw_allow { "redict_port_${i}_v4":
        from => '0.0.0.0/0',
        port => [$redictportnum,$clusterportnum],
      }
    }
  }
}
