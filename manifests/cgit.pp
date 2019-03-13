class sunet::cgit(
  String $package       = 'cgit',
  String $cgitrepo_path = '/home/git/repositories/',
) {
  class { 'sunet::cgit::webserver': }

  file { '/etc/cgitrc':
    content => template('sunet/cgit/cgitrc.erb'),
  }
}
