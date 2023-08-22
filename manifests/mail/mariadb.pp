# Sunet mail db class
class sunet::mail::mariadb () {
  file { '/opt/mariadb/':
    ensure  => directory,
  }
  file { '/opt/mariadb/init/':
    ensure  => directory,
  }
  file { '/opt/mariadb/init/03mail.sql':
    ensure  => file,
    content => template('sunet/mail/mariadb/03mail.erb.sql')
  }
}
