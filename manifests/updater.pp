class sunet::updater($cosmos_automatic_reboot = false, $cron = false) {
   file {'/usr/local/sbin/silent-update-and-upgrade':
     mode    => '0755',
     owner   => 'root',
     group   => 'root',
     content => @("END"/n)
       #!/bin/bash
       export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
       apt-get -qq -y update && env DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confnew' upgrade
       |END
   }
   if ($cosmos_automatic_reboot) {
      file {'/etc/cosmos-automatic-reboot':
         content => "# generated by sunet::updater - do not edit or remove by hand"
      }
   } else {
      file {'/etc/cosmos-automatic-reboot': ensure => absent }
   }
   cron { 'silent-update-and-upgrade': ensure => absent }
   file { '/etc/scriptherder/check/upgrader.ini': ensure => absent }
   if ($cron) {
      sunet::scriptherder::cronjob { 'update_and_upgrade':
         cmd           => '/usr/local/sbin/silent-update-and-upgrade',
         minute        => '2',
         hour          => '4',
         ok_criteria   => ['exit_status=0', 'max_age=25h'],
         warn_criteria => ['exit_status=0', 'max_age=49h'],
      }
   } else {
      sunet::scriptherder::cronjob { 'update_and_upgrade': ensure => absent }
   }
}
