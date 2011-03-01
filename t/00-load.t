#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'App::UnZipK' ) || print "Bail out!
";
}

diag( "Testing App::UnZipK $App::UnZipK::VERSION, Perl $], $^X" );
