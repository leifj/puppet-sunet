# A class to install and manage ClamAV anti-virus software.
class sunet::clamav (
  String $minute = '45',
  String $hour   = '*/2',
) {

  include sunet::packages::clamav
  include sunet::packages::clamav_daemon

  file { '/opt/clamav/':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }
  -> file { '/opt/clamav/scan.sh':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0744',
    content => template('sunet/clamav/scan.erb.sh'),
  }
  -> exec { 'clamav_enable_services':
    command => 'systemctl enable --now clamav-daemon.service clamav-freshclam.service',
    unless  => 'systemctl is-enabled clamav-daemon.service clamav-freshclam.service',
  }
  -> file_line { 'exclude_dev':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/dev/'
  }
  -> file_line { 'exclude_proc':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/proc/'
  }
  -> file_line { 'exclude_sys':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/sys/'
  }
  -> file_line { 'exclude_run':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/run/'
  }
  -> file_line { 'exclude_snap':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/snap/'
  }
  -> file_line { 'exclude_var_snap':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/var/snap/'
  }
  -> file_line { 'exclude_var_lib_docker':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/var/lib/docker'
  }
  -> file_line { 'exclude_opt_backup_mounts':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/opt/backup_mounts'
  }
  -> file_line { 'exclude_var_spool_postfix':
    path => '/etc/clamav/clamd.conf',
    line => 'ExcludePath ^/var/spool/postfix/'
  }
  sunet::scriptherder::cronjob { 'clamav_scan':
    cmd           => '/opt/clamav/scan.sh',
    minute        => $minute,
    hour          => $hour,
    ok_criteria   => ['exit_status=0', 'max_age=3h'],
    warn_criteria => ['exit_status=0', 'max_age=5h'],
  }
}
