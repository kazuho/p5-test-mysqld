requires 'Class::Accessor::Lite';
requires 'File::Copy::Recursive';
requires 'perl', '5.008';

on build => sub {
    requires 'DBD::mysql';
    requires 'DBI';
    requires 'ExtUtils::MakeMaker', '6.59';
    requires 'Test::SharedFork', '0.06';
};
