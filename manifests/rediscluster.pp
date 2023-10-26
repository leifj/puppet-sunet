# A cluster class
class sunet::rediscluster(
  Integer $numnodes = 3,
  Boolean $hostmode = false,
  String $cluster_announce_ip = "",
)
{
  include stdlib

  $redis_password = safe_hiera('redis_password')

  sunet::docker_compose { 'rediscluster_compose':
    content          => template('sunet/rediscluster/docker-compose.yml.erb'),
    service_name     => 'redis',
    compose_dir      => '/opt/',
    compose_filename => 'docker-compose.yml',
    description      => 'Redis Cluster',
  }
  file {'/etc/sysctl.d/55-vm-overcommit.conf':
    ensure  => present,
    content => template('sunet/rediscluster/55-vm-overcommit.conf.erb'),
  }
  range(0, $numnodes - 1).each |$i|{
    $clusterportnum = 16379 + $i
    $redisportnum = 6379 + $i

    file { "/opt/redis/node-${i}":
      ensure  => directory,
    }
    -> file { "/opt/redis/node-${i}/server.conf":
      ensure  => present,
      content => template('sunet/rediscluster/server.conf.erb'),
    }
    -> sunet::misc::ufw_allow { "redis_port_${i}":
      from => 'any',
      port => [$redisportnum,$clusterportnum],
    }
  }
}
