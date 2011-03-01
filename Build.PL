use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name       => 'App::UnZipK',
    license           => 'perl',
    dist_author       => q{Seungwon Jeong <seungwon0@gmail.com>},
    dist_version_from => 'lib/App/UnZipK.pm',
    requires          => {
        'perl'                  => '5.10.0',
        'strict'                => 0,
        'warnings'              => 0,
        'autodie'               => 0,
        'Archive::Zip'          => 0,
        'Encode'                => 0,
        'Getopt::Long'          => 0,
        'Text::Glob'            => 0,
        'File::Spec::Functions' => 0,
        'POSIX'                 => 0,
        'IO::Prompt'            => 0,
        'File::Glob'            => 0,
        'Fcntl'                 => 0,
    },
    build_requires     => { 'Test::More' => 0, },
    script_files       => [ 'bin/unzip-k', ],
    add_to_cleanup     => [ 'unzip-k-*', ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
